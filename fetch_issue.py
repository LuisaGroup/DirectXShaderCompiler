#!/usr/bin/env python3
"""Download a GitHub issue -- title, description, discussion and timeline -- into one Markdown file.

Usage
-----
    python fetch_issue.py 9135
    python fetch_issue.py https://github.com/microsoft/DirectXShaderCompiler/issues/9135
    python fetch_issue.py microsoft/DirectXShaderCompiler#9135 -o issue-9135.md

Data sources
------------
The script has two interchangeable back-ends and always produces the same document:

1. GitHub REST API (``api.github.com``) -- preferred, because it returns the raw
   Markdown source of every post and paginates reliably.  A token is picked up
   from ``--token``, ``$GITHUB_TOKEN``, ``$GH_TOKEN`` or ``gh auth token``.
2. The public issue web page (``github.com``) -- no credentials required.  The
   page ships the whole conversation as JSON inside
   ``<script data-target="react-app.embeddedData">``; further pages of the
   timeline are pulled from the ``/issues/<n>/timeline_items`` endpoint that the
   GitHub web UI itself uses, so comments are *not* truncated.

If the API is rate limited or unauthenticated, the script silently falls back to
the HTML back-end (unless ``--no-api`` is given).

Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from html.parser import HTMLParser
from typing import Dict, List, Optional, Tuple

DEFAULT_REPO = "microsoft/DirectXShaderCompiler"
WEB_ROOT = "https://github.com"
API_ROOT = "https://api.github.com"
USER_AGENT = (
    "fetch_issue.py (+https://github.com/microsoft/DirectXShaderCompiler)"
)

# Emoji used when rendering reactions, keyed by GraphQL *and* REST spelling.
REACTION_EMOJI = {
    "THUMBS_UP": "\U0001F44D",
    "THUMBS_DOWN": "\U0001F44E",
    "LAUGH": "\U0001F604",
    "HOORAY": "\U0001F389",
    "CONFUSED": "\U0001F615",
    "HEART": "\u2764\uFE0F",
    "ROCKET": "\U0001F680",
    "EYES": "\U0001F440",
    "+1": "\U0001F44D",
    "-1": "\U0001F44E",
    "laugh": "\U0001F604",
    "hooray": "\U0001F389",
    "confused": "\U0001F615",
    "heart": "\u2764\uFE0F",
    "rocket": "\U0001F680",
    "eyes": "\U0001F440",
}

# Timeline events that carry no information about the discussion itself.
NOISY_EVENTS = {"subscribed", "unsubscribed", "mentioned"}


# --------------------------------------------------------------------------- #
# Errors / logging
# --------------------------------------------------------------------------- #


class FetchError(RuntimeError):
    """Raised when the issue cannot be downloaded."""


class _Quiet:
    quiet = False
    all_events = False


def log(message: str) -> None:
    if not _Quiet.quiet:
        print(message, file=sys.stderr)


# --------------------------------------------------------------------------- #
# HTTP helpers
# --------------------------------------------------------------------------- #


def http_request(
    url: str,
    headers: Optional[Dict[str, str]] = None,
    timeout: float = 30.0,
    attempts: int = 4,
):
    """GET *url*.

    Returns ``(status, headers, body_bytes)``; retries transient failures and
    returns the final response (including 4xx) instead of raising, so callers can
    inspect status codes.
    """
    hdrs = {"User-Agent": USER_AGENT, "Accept-Language": "en-US,en;q=0.9"}
    if headers:
        hdrs.update(headers)

    delay = 1.0
    last_error = None
    for attempt in range(attempts):
        request = urllib.request.Request(url, headers=hdrs)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.status, dict(response.headers), response.read()
        except urllib.error.HTTPError as exc:
            payload = b""
            try:
                payload = exc.read()
            except Exception:  # pragma: no cover - defensive
                pass
            if exc.code in (429, 500, 502, 503, 504) and attempt + 1 < attempts:
                wait = delay
                retry_after = (exc.headers or {}).get("Retry-After", "")
                if str(retry_after).strip().isdigit():
                    wait = float(retry_after)
                log("  ... HTTP %d from %s, retrying in %.1fs" % (exc.code, url, wait))
                time.sleep(min(wait, 30.0))
                delay *= 2
                continue
            return exc.code, dict(exc.headers or {}), payload
        except (urllib.error.URLError, socket.timeout, TimeoutError) as exc:
            last_error = exc
            if attempt + 1 < attempts:
                log("  ... network error (%s), retrying in %.1fs" % (exc, delay))
                time.sleep(delay)
                delay *= 2
                continue
            raise FetchError("cannot reach %s: %s" % (url, exc))
        except OSError as exc:  # pragma: no cover - defensive
            raise FetchError("cannot reach %s: %s" % (url, exc))
    raise FetchError("cannot reach %s: %s" % (url, last_error))


def http_json(url: str, headers: Optional[Dict[str, str]] = None, timeout: float = 30.0):
    status, resp_headers, body = http_request(url, headers=headers, timeout=timeout)
    if status != 200:
        raise FetchError("GET %s failed with HTTP %d" % (url, status))
    try:
        return json.loads(body.decode("utf-8", "replace"))
    except ValueError as exc:
        raise FetchError("GET %s did not return JSON (%s)" % (url, exc))


# --------------------------------------------------------------------------- #
# Token discovery
# --------------------------------------------------------------------------- #


def _gh_executables() -> List[str]:
    candidates = []
    found = shutil.which("gh")
    if found:
        candidates.append(found)
    if os.name == "nt":
        for base in (
            os.environ.get("ProgramFiles", r"C:\Program Files"),
            os.environ.get("ProgramW6432", r"C:\Program Files"),
            os.environ.get("LOCALAPPDATA", ""),
        ):
            if not base:
                continue
            for rel in (
                os.path.join("GitHub CLI", "gh.exe"),
                os.path.join("Programs", "GitHub CLI", "gh.exe"),
            ):
                candidate = os.path.join(base, rel)
                if os.path.isfile(candidate):
                    candidates.append(candidate)
    return candidates


def discover_token(log_reason: bool = True) -> Tuple[Optional[str], str]:
    """Find a GitHub token.  Returns ``(token, origin)``."""
    for variable in ("GITHUB_TOKEN", "GH_TOKEN"):
        value = os.environ.get(variable)
        if value and value.strip():
            if log_reason:
                log("Using token from $%s" % variable)
            return value.strip(), "$" + variable
    for exe in _gh_executables():
        try:
            completed = subprocess.run(
                [exe, "auth", "token"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=20,
            )
        except Exception:
            continue
        token = (completed.stdout or b"").decode("utf-8", "replace").strip()
        if completed.returncode == 0 and token:
            if log_reason:
                log("Using token from 'gh auth token'")
            return token, "gh auth token"
    return None, ""


# --------------------------------------------------------------------------- #
# Model
# --------------------------------------------------------------------------- #


@dataclass
class Actor:
    login: str = ""
    url: str = ""
    name: str = ""
    bot: bool = False

    def mention(self) -> str:
        if not self.login:
            return self.name or "ghost"
        label = "@" + self.login
        text = "[%s](%s)" % (label, self.url) if self.url else label
        # Bots keep their "[bot]" marker outside the link: nested brackets inside
        # link text would break Markdown parsing.
        if self.bot and "[bot]" not in self.login:
            text += " (bot)"
        return text

    def plain(self) -> str:
        return "@" + self.login if self.login else (self.name or "ghost")


@dataclass
class Comment:
    author: Optional[Actor]
    body: str
    created_at: str = ""
    url: str = ""
    updated_at: str = ""
    association: str = ""
    minimized_reason: str = ""
    reactions: Dict[str, int] = field(default_factory=dict)
    id: str = ""


@dataclass
class Event:
    text: str
    created_at: str = ""
    url: str = ""


@dataclass
class CrossRef:
    kind: str = ""
    number: Optional[int] = None
    url: str = ""
    title: str = ""
    state: str = ""
    is_pr: bool = False
    actor: Optional[Actor] = None
    created_at: str = ""
    note: str = ""


@dataclass
class Issue:
    repo: str
    number: int
    url: str = ""
    title: str = ""
    body: str = ""
    state: str = ""
    state_reason: str = ""
    is_pr: bool = False
    author: Optional[Actor] = None
    created_at: str = ""
    updated_at: str = ""
    closed_at: str = ""
    labels: List[Tuple[str, str]] = field(default_factory=list)
    assignees: List[Actor] = field(default_factory=list)
    milestone: str = ""
    projects: List[str] = field(default_factory=list)
    sub_issues: Optional[Tuple[int, int]] = None
    reactions: Dict[str, int] = field(default_factory=dict)
    comment_count: int = 0
    comments: List[Comment] = field(default_factory=list)
    events: List[Event] = field(default_factory=list)
    cross_refs: List[CrossRef] = field(default_factory=list)
    source: str = ""


# --------------------------------------------------------------------------- #
# Small formatting helpers
# --------------------------------------------------------------------------- #


def fmt_ts(value: str) -> str:
    """Render an ISO-8601 timestamp as ``YYYY-MM-DD HH:MM:SS UTC``."""
    if not value:
        return ""
    cleaned = re.sub(r"\.\d+", "", value.strip())
    for pattern in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S"):
        try:
            parsed = datetime.datetime.strptime(cleaned, pattern)
        except ValueError:
            continue
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone(datetime.timezone.utc)
        return parsed.strftime("%Y-%m-%d %H:%M:%S UTC")
    return value


def fmt_reactions(reactions: Dict[str, int]) -> str:
    parts = []
    for name, count in reactions.items():
        if not count:
            continue
        emoji = REACTION_EMOJI.get(name, name)
        parts.append("%s %d" % (emoji, count))
    return " \u00b7 ".join(parts)


def humanize_event(kind: str) -> str:
    text = re.sub(r"(?<!^)(?=[A-Z])", " ", kind.replace("_", " ")).strip()
    return text[:1].upper() + text[1:].lower()


def shorten(text: str, limit: int = 100) -> str:
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "\u2026"


def first_line(text: str) -> str:
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()
    return ""


# --------------------------------------------------------------------------- #
# HTML -> Markdown (used only when a raw Markdown body is unavailable)
# --------------------------------------------------------------------------- #


class _MarkdownConverter(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.lines: List[str] = []
        self.cur: List[str] = []
        self.prefix: List[str] = []
        self.pre_depth = 0
        self.pre_buf: List[str] = []
        self.pre_lang = ""
        self.code_depth = 0
        self.link_stack: List[str] = []
        self.list_stack: List[str] = []
        self.list_counters: List[int] = []
        self.table: Optional[List[List[str]]] = None
        self.row: Optional[List[str]] = None
        self.cell: Optional[List[str]] = None
        self.skip_depth = 0

    # -- output plumbing ---------------------------------------------------- #
    def _line_start(self) -> None:
        if not self.cur:
            self.cur.extend(self.prefix)

    def write(self, text: str) -> None:
        if not text or self.skip_depth:
            return
        if self.cell is not None:
            self.cell.append(text)
            return
        at_line_start = not self.cur
        self._line_start()
        self.cur.append(text.lstrip() if at_line_start else text)

    def newline(self) -> None:
        line = "".join(self.cur).rstrip()
        self.lines.append(line)
        self.cur = []

    def blank(self) -> None:
        if self.cur:
            self.newline()
        if self.lines and self.lines[-1] != "":
            self.lines.append("")

    # -- parser callbacks --------------------------------------------------- #
    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag in ("script", "style", "head", "template"):
            self.skip_depth += 1
            return
        if self.skip_depth:
            return

        if tag == "pre":
            self.blank()
            self.pre_depth += 1
            self.pre_buf = []
            self.pre_lang = ""
            return
        if tag == "code":
            if self.pre_depth:
                classes = (attributes.get("class") or "").split()
                for name in classes:
                    if name.startswith("language-"):
                        self.pre_lang = name[len("language-"):]
                        break
                return
            self.code_depth += 1
            self.write("`")
            return
        if tag in ("p", "div", "section", "article", "details", "summary"):
            self.blank()
            return
        if tag == "br":
            self.newline()
            return
        if tag in ("strong", "b"):
            self.write("**")
            return
        if tag in ("em", "i"):
            self.write("*")
            return
        if tag in ("del", "s", "strike"):
            self.write("~~")
            return
        if tag == "a":
            href = attributes.get("href") or ""
            self.link_stack.append(href)
            self.write("[")
            return
        if tag == "img":
            alt = attributes.get("alt") or ""
            src = attributes.get("src") or ""
            if src:
                self.write("![%s](%s)" % (alt, src))
            return
        if tag in ("ul", "ol"):
            self.blank()
            self.list_stack.append(tag)
            self.list_counters.append(0)
            return
        if tag == "li":
            self.blank()
            depth = max(len(self.list_stack) - 1, 0)
            indent = "  " * depth
            if self.list_stack and self.list_stack[-1] == "ol":
                self.list_counters[-1] += 1
                marker = "%d. " % self.list_counters[-1]
            else:
                marker = "- "
            self.write(indent + marker)
            return
        if tag == "blockquote":
            self.blank()
            self.prefix.append("> ")
            return
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.blank()
            self.write("#" * int(tag[1]) + " ")
            return
        if tag == "hr":
            self.blank()
            self.write("---")
            self.newline()
            return
        if tag == "table":
            self.blank()
            self.table = []
            return
        if tag == "tr":
            self.row = []
            return
        if tag in ("td", "th"):
            self.cell = []
            return
        if tag == "input":
            if (attributes.get("type") or "").lower() == "checkbox":
                self.write("[x] " if "checked" in attributes else "[ ] ")
            return

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head", "template"):
            if self.skip_depth:
                self.skip_depth -= 1
            return
        if self.skip_depth:
            return

        if tag == "pre":
            if self.pre_depth:
                self.pre_depth -= 1
                code = "".join(self.pre_buf).strip("\n")
                self.pre_buf = []
                longest = max([len(run) for run in re.findall(r"`+", code)] or [0])
                fence = "`" * max(3, longest + 1)
                self.blank()
                self.lines.append(fence + self.pre_lang)
                self.lines.extend(code.splitlines() or [""])
                self.lines.append(fence)
                self.lines.append("")
            return
        if tag == "code":
            if self.pre_depth:
                return
            if self.code_depth:
                self.code_depth -= 1
            self.write("`")
            return
        if tag in ("p", "div", "section", "article", "details"):
            self.blank()
            return
        if tag == "summary":
            self.blank()
            return
        if tag in ("strong", "b"):
            self.write("**")
            return
        if tag in ("em", "i"):
            self.write("*")
            return
        if tag in ("del", "s", "strike"):
            self.write("~~")
            return
        if tag == "a":
            href = self.link_stack.pop() if self.link_stack else ""
            self.write("](%s)" % href if href else "]")
            return
        if tag in ("ul", "ol"):
            if self.list_stack:
                self.list_stack.pop()
            if self.list_counters:
                self.list_counters.pop()
            self.blank()
            return
        if tag == "li":
            self.blank()
            return
        if tag == "blockquote":
            if self.prefix:
                self.prefix.pop()
            self.blank()
            return
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.blank()
            return
        if tag in ("td", "th"):
            if self.cell is not None and self.row is not None:
                text = " ".join("".join(self.cell).split())
                self.row.append(text.replace("|", "\\|"))
            self.cell = None
            return
        if tag == "tr":
            if self.row is not None and self.table is not None:
                self.table.append(self.row)
            self.row = None
            return
        if tag == "table":
            if self.table:
                rows = [row for row in self.table if row]
                if rows:
                    width = max(len(row) for row in rows)
                    rows = [row + [""] * (width - len(row)) for row in rows]
                    self.lines.append("| " + " | ".join(rows[0]) + " |")
                    self.lines.append("| " + " | ".join(["---"] * width) + " |")
                    for row in rows[1:]:
                        self.lines.append("| " + " | ".join(row) + " |")
                    self.lines.append("")
            self.table = None
            return

    def handle_data(self, data):
        if self.skip_depth:
            return
        if self.pre_depth:
            self.pre_buf.append(data)
            return
        if self.cell is not None:
            self.cell.append(" ".join(data.split(" ")))
            return
        self.write(re.sub(r"[ \t\r\n]+", " ", data))

    def result(self) -> str:
        if self.cur:
            self.newline()
        while self.lines and self.lines[-1] == "":
            self.lines.pop()
        text = "\n".join(self.lines)
        text = re.sub(r"[ \t]+\n", "\n", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()


def html_to_markdown(html: str) -> str:
    if not html:
        return ""
    converter = _MarkdownConverter()
    try:
        converter.feed(html)
        converter.close()
        return converter.result()
    except Exception:  # pragma: no cover - the raw Markdown body is preferred anyway
        text = re.sub(r"<br\s*/?>", "\n", html)
        text = re.sub(r"</p\s*>", "\n\n", text)
        text = re.sub(r"<[^>]+>", "", text)
        return re.sub(r"\n{3,}", "\n\n", text).strip()


def body_from(payload: Dict) -> str:
    """Prefer GitHub's raw Markdown over the rendered HTML."""
    body = payload.get("body")
    if isinstance(body, str) and body.strip():
        return body.rstrip()
    html = payload.get("bodyHTML") or payload.get("body_html") or ""
    return html_to_markdown(html).rstrip()


# --------------------------------------------------------------------------- #
# Actor helpers
# --------------------------------------------------------------------------- #


def actor_from_graphql(node) -> Optional[Actor]:
    if not isinstance(node, dict):
        return None
    login = node.get("login") or ""
    url = node.get("profileUrl") or node.get("url") or ""
    resource = node.get("profileResourcePath") or node.get("resourcePath") or ""
    if not url and resource:
        url = WEB_ROOT + resource
    if not url and login:
        url = WEB_ROOT + "/" + login
    typename = node.get("__typename") or node.get("type") or ""
    return Actor(
        login=login,
        url=url,
        name=node.get("name") or node.get("displayName") or "",
        bot=typename == "Bot",
    )


def actor_from_rest(node) -> Optional[Actor]:
    if not isinstance(node, dict):
        return None
    login = node.get("login") or ""
    return Actor(
        login=login,
        url=node.get("html_url") or (WEB_ROOT + "/" + login if login else ""),
        name=node.get("name") or "",
        bot=(node.get("type") == "Bot"),
    )


# --------------------------------------------------------------------------- #
# Event / cross-reference description
# --------------------------------------------------------------------------- #


def describe_event(
    kind: str,
    actor: Optional[Actor] = None,
    label: Optional[str] = None,
    assignee: Optional[Actor] = None,
    milestone: Optional[str] = None,
    project: Optional[str] = None,
    from_title: str = "",
    to_title: str = "",
    state_reason: str = "",
    closer: Optional[CrossRef] = None,
    source: Optional[CrossRef] = None,
    commit_sha: str = "",
    commit_message: str = "",
    duplicate_of: Optional[int] = None,
) -> str:
    """Build the body of one timeline bullet (actor included, timestamp excluded)."""
    who = actor.mention() if actor and actor.login else "someone"
    kind = kind.lower()

    if kind == "labeled":
        return "%s added the %s label" % (who, "`%s`" % label if label else "a")
    if kind == "unlabeled":
        return "%s removed the %s label" % (who, "`%s`" % label if label else "a")
    if kind == "assigned":
        return "%s assigned %s" % (who, assignee.mention() if assignee else "themselves")
    if kind == "unassigned":
        return "%s unassigned %s" % (who, assignee.mention() if assignee else "a user")
    if kind == "closed":
        text = "%s closed this issue" % who
        if state_reason:
            text += " as `%s`" % state_reason.lower().replace("_", " ")
        if closer is not None:
            text += " via %s" % _ref_link(closer)
        return text
    if kind == "reopened":
        return "%s reopened this issue" % who
    if kind in ("renamed", "renamed_title", "renamedtitle"):
        return "%s changed the title from **%s** to **%s**" % (
            who,
            shorten(from_title, 80) or "?",
            shorten(to_title, 80) or "?",
        )
    if kind == "milestoned":
        return "%s added this issue to the %s milestone" % (
            who,
            "`%s`" % milestone if milestone else "a",
        )
    if kind == "demilestoned":
        return "%s removed this issue from the %s milestone" % (
            who,
            "`%s`" % milestone if milestone else "the",
        )
    if kind in ("added_to_project_v2", "added_to_project"):
        return "%s added this issue to %s" % (who, _project_phrase(project))
    if kind in ("removed_from_project_v2", "removed_from_project"):
        return "%s removed this issue from %s" % (who, _project_phrase(project))
    if kind in ("marked_as_duplicate",):
        return "%s marked this issue as a duplicate of #%s" % (who, duplicate_of or "?")
    if kind in ("referenced",):
        text = "%s referenced this issue" % who
        if commit_sha:
            short_sha = commit_sha[:7]
            if commit_message:
                text += " in commit `%s` (%s)" % (short_sha, shorten(first_line(commit_message), 70))
            else:
                text += " in commit `%s`" % short_sha
        return text
    if kind in ("cross-referenced", "crossreferenced", "cross_referenced"):
        return "%s cross-referenced this from %s" % (
            who,
            _ref_link(source) if source is not None else "another thread",
        )
    if kind in ("pinned", "pinned_issue"):
        return "%s pinned this issue" % who
    if kind in ("unpinned", "unpinned_issue"):
        return "%s unpinned this issue" % who
    if kind == "locked":
        return "%s locked the conversation" % who
    if kind == "unlocked":
        return "%s unlocked the conversation" % who
    if kind in ("commented", "issuecomment"):
        return "%s commented" % who
    if kind in ("reviewed",):
        return "%s reviewed" % who
    if kind in ("review_requested",):
        return "%s requested a review" % who
    if kind in ("head_ref_force_pushed",):
        return "%s force-pushed the branch" % who
    if kind in ("comment_deleted",):
        return "%s deleted a comment" % who
    if kind in ("user_blocked",):
        return "%s blocked a user" % who
    if kind in ("transferred", "transfered"):
        return "%s transferred this issue" % who
    if kind in ("converted_note_to_issue",):
        return "%s converted a note into this issue" % who
    if kind in ("unmarked_as_duplicate",):
        return "%s removed the duplicate mark" % who
    if kind in ("moved_columns_in_project",):
        return "%s moved this issue in a project" % who
    if kind in ("subscribed",):
        return "%s subscribed" % who
    if kind in ("unsubscribed",):
        return "%s unsubscribed" % who
    if kind in ("mentioned",):
        return "%s mentioned this issue" % who
    if kind in ("autoclosed", "auto_closed"):
        return "%s closed this issue automatically" % who
    if kind in ("autoreopen", "auto_reopen"):
        return "%s reopened this issue automatically" % who

    return "%s triggered %s" % (who, humanize_event(kind))


def _project_phrase(project) -> str:
    """Render a project reference (tuple of title/url, plain string, or nothing)."""
    if isinstance(project, tuple):
        title, url = (project + ("", ""))[:2]
        if title and url:
            return "the [%s](%s) project" % (title, url)
        if title:
            return "the %s project" % title
        if url:
            return "the [project](%s)" % url
        return "a project"
    if isinstance(project, str) and project.strip():
        value = project.strip()
        if value.startswith("http"):
            name = value.rstrip("/").rsplit("/", 1)[-1]
            return "the [project %s](%s)" % (name, value)
        return "the %s project" % value
    return "a project"


def _ref_link(ref: Optional[CrossRef]) -> str:
    if ref is None:
        return ""
    label = ref.title or ("#%s" % ref.number if ref.number else ref.url)
    text = "[%s](%s)" % (label, ref.url) if ref.url else label
    if ref.is_pr and ref.number and not ref.title:
        text = "[#%s](%s)" % (ref.number, ref.url) if ref.url else "#%s" % ref.number
    extra = []
    if ref.state:
        extra.append(ref.state.lower())
    if ref.note:
        extra.append(ref.note)
    if extra:
        text += " (%s)" % ", ".join(extra)
    return text


# --------------------------------------------------------------------------- #
# Back-end 1: GitHub REST API
# --------------------------------------------------------------------------- #


def _api_headers(token: Optional[str]) -> Dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = "Bearer " + token
    return headers


def _api_paginate(url: str, headers: Dict[str, str], max_pages: int, timeout: float,
                  what: str) -> List[Dict]:
    items: List[Dict] = []
    page = 1
    while page <= max_pages:
        separator = "&" if "?" in url else "?"
        payload = http_json("%s%sper_page=100&page=%d" % (url, separator, page),
                            headers=headers, timeout=timeout)
        if not isinstance(payload, list):
            break
        items.extend(payload)
        if len(payload) < 100:
            break
        page += 1
    else:
        log("  ... %s truncated at %d pages (--max-pages)" % (what, max_pages))
    return items


def fetch_via_api(repo: str, number: int, token: Optional[str], max_pages: int,
                  timeout: float) -> Issue:
    headers = _api_headers(token)
    base = "%s/repos/%s/issues/%d" % (API_ROOT, repo, number)

    status, resp_headers, body = http_request(base, headers=headers, timeout=timeout)
    if status == 404:
        raise FetchError(
            "issue #%d was not found in %s (or the repository is private)." % (number, repo)
        )
    if status == 403:
        remaining = resp_headers.get("X-RateLimit-Remaining", "")
        raise FetchError(
            "GitHub API returned 403 (rate limit remaining: %s)" % (remaining or "?")
        )
    if status == 401:
        raise FetchError("GitHub API rejected the token (HTTP 401)")
    if status != 200:
        raise FetchError("GitHub API returned HTTP %d for %s" % (status, base))

    raw = json.loads(body.decode("utf-8", "replace"))
    issue = Issue(repo=repo, number=number, source="GitHub REST API v3")
    issue.url = raw.get("html_url") or "%s/%s/issues/%d" % (WEB_ROOT, repo, number)
    issue.title = raw.get("title") or ""
    issue.body = (raw.get("body") or "").rstrip()
    issue.state = (raw.get("state") or "").lower()
    issue.state_reason = raw.get("state_reason") or ""
    issue.is_pr = "pull_request" in raw
    issue.author = actor_from_rest(raw.get("user"))
    issue.created_at = raw.get("created_at") or ""
    issue.updated_at = raw.get("updated_at") or ""
    issue.closed_at = raw.get("closed_at") or ""
    issue.comment_count = int(raw.get("comments") or 0)
    for label in raw.get("labels") or []:
        if isinstance(label, dict):
            issue.labels.append((label.get("name") or "", label.get("description") or ""))
        else:
            issue.labels.append((str(label), ""))
    for assignee in raw.get("assignees") or []:
        actor = actor_from_rest(assignee)
        if actor:
            issue.assignees.append(actor)
    milestone = raw.get("milestone") or {}
    if isinstance(milestone, dict):
        issue.milestone = milestone.get("title") or ""
    reactions = raw.get("reactions") or {}
    issue.reactions = {
        key: int(value)
        for key, value in reactions.items()
        if key in REACTION_EMOJI and isinstance(value, int)
    }

    start = time.time()
    comments_raw = _api_paginate(base + "/comments", headers, max_pages, timeout, "comments")
    for item in comments_raw:
        comment = Comment(
            author=actor_from_rest(item.get("user")),
            body=(item.get("body") or "").rstrip(),
            created_at=item.get("created_at") or "",
            updated_at=item.get("updated_at") or "",
            url=item.get("html_url") or "",
            association=(item.get("author_association") or ""),
            id=str(item.get("id") or ""),
        )
        comment.reactions = {
            key: int(value)
            for key, value in (item.get("reactions") or {}).items()
            if key in REACTION_EMOJI and isinstance(value, int)
        }
        issue.comments.append(comment)
    if not issue.comment_count:
        issue.comment_count = len(issue.comments)

    timeline_url = base + "/timeline"
    try:
        timeline = _api_paginate(timeline_url, headers, max_pages, timeout, "timeline")
    except FetchError as exc:
        log("  ! could not read the timeline: %s" % exc)
        timeline = []
    _absorb_rest_timeline(issue, timeline, repo)
    log("  API fetch took %.1fs (%d comments, %d timeline events)"
        % (time.time() - start, len(issue.comments), len(issue.events)))
    return issue


def _absorb_rest_timeline(issue: Issue, timeline: List[Dict], repo: str) -> None:
    for entry in timeline:
        kind = (entry.get("event") or "").lower()
        actor = actor_from_rest(entry.get("actor"))
        created = entry.get("created_at") or ""
        if kind == "commented":
            continue  # already collected from /comments
        source = None
        if kind == "cross-referenced":
            raw_source = entry.get("source") or {}
            raw_issue = raw_source.get("issue") or {}
            is_pr = bool(raw_issue.get("pull_request"))
            source = CrossRef(
                kind="cross-referenced",
                number=raw_issue.get("number"),
                url=raw_issue.get("html_url") or "",
                title=raw_issue.get("title") or "",
                state=raw_issue.get("state") or "",
                is_pr=is_pr,
                actor=actor,
                created_at=created,
                note="pull request" if is_pr else "issue",
            )
            issue.cross_refs.append(source)
        elif kind == "referenced":
            sha = entry.get("commit_id") or ""
            if sha:
                source = CrossRef(
                    kind="referenced",
                    url="%s/%s/commit/%s" % (WEB_ROOT, repo, sha),
                    title="commit %s" % sha[:7],
                    actor=actor,
                    created_at=created,
                )
        elif kind == "closed":
            closer_pr = entry.get("source") or {}
            raw_issue = closer_pr.get("issue") if isinstance(closer_pr, dict) else None
            if isinstance(raw_issue, dict) and raw_issue.get("number"):
                source = CrossRef(
                    kind="closed-by",
                    number=raw_issue.get("number"),
                    url=raw_issue.get("html_url") or "",
                    title=raw_issue.get("title") or "",
                    state=raw_issue.get("state") or "",
                    is_pr=bool(raw_issue.get("pull_request")),
                )
        elif kind in ("marked_as_duplicate",):
            pass

        if kind in NOISY_EVENTS and not _Quiet.all_events:
            # still record cross-references/mentions separately, just no timeline bullet
            continue

        label = entry.get("label", {}).get("name") if isinstance(entry.get("label"), dict) else None
        assignee = actor_from_rest(entry.get("assignee"))
        milestone = entry.get("milestone", {}).get("title") if isinstance(entry.get("milestone"), dict) else None
        project = None
        if isinstance(entry.get("project_card"), dict):
            project = entry["project_card"].get("project_url") or ""
        rename = entry.get("rename") if isinstance(entry.get("rename"), dict) else {}
        closed_reason = entry.get("state_reason") or ""
        if kind == "closed" and not closed_reason and issue.state == "closed":
            # The REST timeline event does not always carry the resolution; the
            # issue itself does, so fall back to it for the final close.
            closed_reason = issue.state_reason

        text = describe_event(
            kind,
            actor=actor,
            label=label,
            assignee=assignee,
            milestone=milestone,
            project=project,
            from_title=rename.get("from") or "",
            to_title=rename.get("to") or "",
            state_reason=closed_reason,
            closer=source if kind == "closed" else None,
            source=source,
            commit_sha=entry.get("commit_id") or "",
            duplicate_of=(entry.get("source") or {}).get("issue", {}).get("number")
            if kind == "marked_as_duplicate" and isinstance(entry.get("source"), dict)
            else None,
        )
        issue.events.append(Event(text=text, created_at=created, url=entry.get("url") or ""))


# --------------------------------------------------------------------------- #
# Back-end 2: public issue page (embedded React payload + timeline_items)
# --------------------------------------------------------------------------- #

_EMBEDDED_TARGET = "react-app.embeddedData"
_TIMELINE_ENDPOINT = "%s/%s/issues/%d/timeline_items"


def _extract_embedded_payload(html: str) -> Optional[Dict]:
    for match in re.finditer(r"<script\b([^>]*)>(.*?)</script>", html, re.S | re.I):
        attributes = match.group(1)
        if _EMBEDDED_TARGET not in attributes:
            continue
        if "application/json" not in attributes:
            continue
        try:
            return json.loads(match.group(2))
        except ValueError:
            continue
    return None


def _find_issue_node(obj) -> Optional[Dict]:
    """Locate the dict describing the issue, whatever the route wrapper is."""
    if isinstance(obj, dict):
        if "number" in obj and ("timelineItems" in obj or "bodyHTML" in obj) and "title" in obj:
            return obj
        for value in obj.values():
            found = _find_issue_node(value)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = _find_issue_node(value)
            if found is not None:
                return found
    return None


def _timeline_nodes(container) -> Tuple[List[Dict], Dict]:
    edges = ((container or {}).get("edges") or []) if isinstance(container, dict) else []
    nodes = [edge.get("node") for edge in edges if isinstance(edge, dict) and edge.get("node")]
    page_info = (container or {}).get("pageInfo") or {} if isinstance(container, dict) else {}
    return nodes, page_info


def fetch_via_html(repo: str, number: int, max_pages: int, timeout: float) -> Issue:
    page_url = "%s/%s/issues/%d" % (WEB_ROOT, repo, number)
    status, _headers, body = http_request(
        page_url, headers={"Accept": "text/html,application/xhtml+xml"}, timeout=timeout
    )
    if status == 404:
        raise FetchError("issue #%d was not found in %s (HTTP 404)." % (number, repo))
    if status != 200:
        raise FetchError("GET %s returned HTTP %d" % (page_url, status))

    html = body.decode("utf-8", "replace")
    payload = _extract_embedded_payload(html)
    if payload is None:
        raise FetchError("could not find the embedded issue data in %s" % page_url)

    routes = payload.get("payload") or {}
    if isinstance(routes, dict) and "pullRequestsConversationsRoute" in routes:
        raise FetchError(
            "%s/%d is a pull request; the HTML back-end only handles issues. "
            "Re-run with a GitHub token (rest API) to fetch pull requests."
            % (repo, number)
        )

    node = _find_issue_node(payload)
    if node is None:
        raise FetchError("could not locate the issue payload in %s" % page_url)

    issue = Issue(repo=repo, number=int(node.get("number") or number),
                  source="github.com issue page")
    issue.url = node.get("url") or page_url
    issue.title = node.get("title") or ""
    issue.body = body_from(node)
    issue.state = (node.get("state") or "").lower()
    reason = node.get("stateReason") or ""
    issue.state_reason = reason.lower().replace("_", " ") if reason else ""
    issue.is_pr = (node.get("__isIssueOrPullRequest") or "").lower() == "pullrequest"
    issue.author = actor_from_graphql(node.get("author"))
    issue.created_at = node.get("createdAt") or ""
    issue.updated_at = node.get("updatedAt") or ""
    issue.comment_count = int(node.get("totalCommentsCount") or 0)

    for edge in ((node.get("labels") or {}).get("edges") or []):
        label = (edge or {}).get("node") or {}
        if label:
            issue.labels.append((label.get("name") or "", label.get("description") or ""))

    for assignee in ((node.get("assignedActors") or {}).get("nodes") or []):
        actor = actor_from_graphql(assignee)
        if actor:
            issue.assignees.append(actor)

    milestone = node.get("milestone")
    if isinstance(milestone, dict):
        issue.milestone = milestone.get("title") or ""

    for edge in ((node.get("projectItems") or {}).get("edges") or []):
        item = (edge or {}).get("node") or {}
        project = item.get("project") or {}
        title = project.get("title") or ""
        url = project.get("url") or ""
        if not title:
            continue
        value = item.get("fieldValueByName")
        status_value = ""
        if isinstance(value, dict):
            status_value = (value.get("name") or value.get("title") or value.get("text")
                            or value.get("optionName") or "")
        entry = "[%s](%s)" % (title, url) if url else title
        if status_value:
            entry += " \u2014 status: `%s`" % status_value
        issue.projects.append(entry)

    summary = node.get("subIssuesSummary") or {}
    if isinstance(summary, dict) and summary.get("total"):
        issue.sub_issues = (int(summary.get("completed") or 0), int(summary.get("total") or 0))

    for group in node.get("reactionGroups") or []:
        content = group.get("content") or ""
        count = int(((group.get("reactors") or {}).get("totalCount")) or 0)
        if content and count:
            issue.reactions[content] = count

    for key in ("linkedPullRequests", "closedByPullRequestsReferences"):
        for pr in (((node.get(key) or {}).get("nodes")) or []):
            if not isinstance(pr, dict):
                continue
            number_value = pr.get("number")
            url = pr.get("url") or pr.get("permalink") or ""
            if not url and pr.get("resourcePath"):
                url = WEB_ROOT + pr["resourcePath"]
            issue.cross_refs.append(
                CrossRef(
                    kind="linked-pull-request" if key == "linkedPullRequests" else "closed-by",
                    number=number_value,
                    url=url,
                    title=pr.get("title") or "",
                    state=pr.get("state") or "",
                    is_pr=True,
                    note="pull request",
                )
            )

    nodes, page_info = _timeline_nodes(node.get("timelineItems"))
    seen = set()
    ordered: List[Dict] = []
    for item in nodes:
        key = item.get("id") or id(item)
        if key in seen:
            continue
        seen.add(key)
        ordered.append(item)

    endpoint = _TIMELINE_ENDPOINT % (WEB_ROOT, repo, number)
    pages = 0
    while page_info.get("hasNextPage") and pages < max_pages:
        pages += 1
        cursor = page_info.get("endCursor")
        if not cursor:
            break
        try:
            data = http_json("%s?after=%s" % (endpoint, urllib.parse.quote(cursor)), timeout=timeout)
        except FetchError as exc:
            log("  ! timeline pagination stopped: %s" % exc)
            break
        container = (((data.get("data") or {}).get("repository") or {}).get("issue") or {}).get("timelineItems")
        batch, page_info = _timeline_nodes(container)
        if not batch:
            break
        added = 0
        for item in batch:
            key = item.get("id") or id(item)
            if key in seen:
                continue
            seen.add(key)
            ordered.append(item)
            added += 1
        if not added:
            break

    if page_info.get("hasNextPage"):
        log("  ! timeline truncated at %d pages (--max-pages)" % max_pages)
    if page_info.get("hasPreviousPage"):
        log("  ! the timeline was loaded mid-thread; the first items may be missing")

    for item in ordered:
        typename = item.get("__typename") or ""
        if typename == "IssueComment":
            comment = Comment(
                author=actor_from_graphql(item.get("author")),
                body=body_from(item),
                created_at=item.get("createdAt") or "",
                updated_at=item.get("lastEditedAt") or "",
                url=item.get("url") or "",
                association=item.get("authorAssociation") or "",
                minimized_reason=(item.get("minimizedReason") or "")
                if item.get("isMinimized")
                else "",
                id=str(item.get("id") or ""),
            )
            for group in item.get("reactionGroups") or []:
                content = group.get("content") or ""
                count = int(((group.get("reactors") or {}).get("totalCount")) or 0)
                if content and count:
                    comment.reactions[content] = count
            issue.comments.append(comment)
            continue

        if typename == "ClosedEvent" and item.get("createdAt"):
            issue.closed_at = issue.closed_at or item["createdAt"]
        _absorb_graphql_event(issue, typename, item, repo)

    if not issue.comment_count:
        issue.comment_count = len(issue.comments)
    return issue


def _absorb_graphql_event(issue: Issue, typename: str, item: Dict, repo: str) -> None:
    kind = re.sub(r"Event$", "", typename)
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", kind).lower()
    actor = actor_from_graphql(item.get("actor"))
    created = item.get("createdAt") or ""

    if snake in ("subscribed", "unsubscribed", "mentioned") and not _Quiet.all_events:
        return

    source = None
    commit_sha = ""
    commit_message = ""
    closer = None

    if snake in ("cross_referenced", "crossreferenced"):
        raw_source = item.get("source") or {}
        is_pr = (raw_source.get("__typename") or "") == "PullRequest"
        url = raw_source.get("url") or raw_source.get("permalink") or ""
        if not url and raw_source.get("resourcePath"):
            url = WEB_ROOT + raw_source["resourcePath"]
        source = CrossRef(
            kind="cross-referenced",
            number=raw_source.get("number"),
            url=url,
            title=raw_source.get("title") or "",
            state=raw_source.get("state") or "",
            is_pr=is_pr,
            actor=actor,
            created_at=created,
            note="pull request" if is_pr else "issue",
        )
        issue.cross_refs.append(source)
    elif snake == "referenced":
        commit = item.get("commit") or {}
        commit_sha = commit.get("oid") or commit.get("abbreviatedOid") or ""
        commit_message = commit.get("message") or ""
    elif snake == "closed":
        raw_closer = item.get("closer") or {}
        if isinstance(raw_closer, dict) and raw_closer.get("number"):
            closer = CrossRef(
                kind="closed-by",
                number=raw_closer.get("number"),
                url=raw_closer.get("url") or raw_closer.get("permalink") or "",
                title=raw_closer.get("title") or "",
                state=raw_closer.get("state") or "",
                is_pr=(raw_closer.get("__typename") or "") == "PullRequest",
                note="pull request",
            )
            issue.cross_refs.append(closer)

    project = None
    raw_project = item.get("project")
    if isinstance(raw_project, dict):
        project = (raw_project.get("title") or "", raw_project.get("url") or "")

    label = None
    if isinstance(item.get("label"), dict):
        label = item["label"].get("name")
    milestone = None
    if isinstance(item.get("milestone"), dict):
        milestone = item["milestone"].get("title")

    duplicate_of = None
    raw_dup = item.get("duplicateOf") or item.get("canonical")
    if isinstance(raw_dup, dict):
        duplicate_of = raw_dup.get("number")

    text = describe_event(
        snake,
        actor=actor,
        label=label,
        assignee=actor_from_graphql(item.get("assignee")),
        milestone=milestone,
        project=project,
        from_title=item.get("previousTitle") or item.get("fromTitle") or "",
        to_title=item.get("currentTitle") or item.get("toTitle") or "",
        state_reason=item.get("stateReason") or "",
        closer=closer,
        source=source,
        commit_sha=commit_sha,
        commit_message=commit_message,
        duplicate_of=duplicate_of,
    )
    issue.events.append(Event(text=text, created_at=created, url=item.get("url") or ""))


# --------------------------------------------------------------------------- #
# Rendering
# --------------------------------------------------------------------------- #

_ASSOCIATION_LABELS = {
    "OWNER": "owner",
    "MEMBER": "member",
    "COLLABORATOR": "collaborator",
    "CONTRIBUTOR": "contributor",
    "FIRST_TIME_CONTRIBUTOR": "first-time contributor",
    "FIRST_TIMER": "first-time contributor",
    "MANNEQUIN": "unclaimed account",
    "NONE": "",
}


def _association(value: str) -> str:
    return _ASSOCIATION_LABELS.get((value or "").upper(), (value or "").lower())


def render_markdown(issue: Issue) -> str:
    repo_url = "%s/%s" % (WEB_ROOT, issue.repo)
    title = issue.title or "(untitled)"
    out: List[str] = []

    out.append("# %s" % title)
    out.append("")
    out.append("> **%s#%d** \u00b7 %s \u00b7 opened by %s on %s"
               % (
                   issue.repo,
                   issue.number,
                   ("`%s`" % (issue.state or "unknown"))
                   + (" (%s)" % issue.state_reason if issue.state_reason else ""),
                   issue.author.mention() if issue.author and issue.author.login else "an unknown author",
                   fmt_ts(issue.created_at) or "an unknown date",
               ))
    out.append("")

    facts = []
    facts.append(("Issue", "[#%d](%s)" % (issue.number, issue.url)))
    facts.append(("Repository", "[%s](%s)" % (issue.repo, repo_url)))
    facts.append(("State", "`%s`%s" % (issue.state or "unknown",
                                       " (%s)" % issue.state_reason if issue.state_reason else "")))
    if issue.author and (issue.author.login or issue.author.name):
        author = issue.author.mention()
        if issue.author.name:
            author += " (%s)" % issue.author.name
        facts.append(("Author", author))
    facts.append(("Created", fmt_ts(issue.created_at) or "-"))
    facts.append(("Updated", fmt_ts(issue.updated_at) or "-"))
    if issue.closed_at:
        facts.append(("Closed", fmt_ts(issue.closed_at)))
    facts.append(("Comments", str(issue.comment_count)))
    if issue.labels:
        rendered = []
        for name, description in issue.labels:
            rendered.append("`%s`" % name + (" (%s)" % description if description else ""))
        facts.append(("Labels", ", ".join(rendered)))
    if issue.milestone:
        facts.append(("Milestone", issue.milestone))
    if issue.assignees:
        facts.append(("Assignees", ", ".join(a.mention() for a in issue.assignees)))
    if issue.projects:
        facts.append(("Projects", "; ".join(issue.projects)))
    linked = [ref for ref in issue.cross_refs if ref.kind == "linked-pull-request"]
    if linked:
        facts.append(("Linked pull requests", ", ".join(_ref_link(r) for r in linked)))
    if issue.sub_issues:
        facts.append(("Sub-issues", "%d of %d completed" % issue.sub_issues))
    reactions = fmt_reactions(issue.reactions)
    if reactions:
        facts.append(("Reactions", reactions))
    facts.append(("Source", issue.source or "-"))

    participants = _participants(issue)
    if participants:
        facts.append(("Participants", participants))

    for key, value in facts:
        out.append("- **%s:** %s" % (key, value))

    if issue.comment_count and len(issue.comments) < issue.comment_count:
        out.append(
            "- **Note:** only %d of %d comments are included (page limit reached; "
            "raise --max-pages to fetch the rest)"
            % (len(issue.comments), issue.comment_count)
        )
    if issue.is_pr:
        out.append(
            "- **Note:** this URL is a pull request; review threads and review "
            "comments are not part of this document"
        )
    out.append("")

    out.append("---")
    out.append("")
    out.append("## Description")
    out.append("")
    out.append(issue.body.strip() if issue.body.strip() else "_No description provided._")
    out.append("")
    out.append("---")
    out.append("")
    out.append("## Discussion")
    out.append("")

    if not issue.comments:
        out.append("_No comments on this issue._")
        out.append("")
    else:
        total = len(issue.comments)
        for index, comment in enumerate(issue.comments, start=1):
            author = (comment.author.mention() if comment.author and comment.author.login
                      else "an unknown author")
            out.append("### Comment %d of %d \u2014 %s \u00b7 %s"
                       % (index, total, author, fmt_ts(comment.created_at) or "unknown date"))
            out.append("")
            meta = []
            association = _association(comment.association)
            if association and association != "none":
                meta.append(association)
            if comment.updated_at and comment.updated_at != comment.created_at:
                meta.append("edited %s" % fmt_ts(comment.updated_at))
            if comment.minimized_reason:
                meta.append("_hidden by a moderator: %s_"
                            % comment.minimized_reason.lower().replace("_", " "))
            reaction_text = fmt_reactions(comment.reactions)
            if reaction_text:
                meta.append(reaction_text)
            if comment.url:
                meta.append("[permalink](%s)" % comment.url)
            if meta:
                out.append("_%s_" % " \u00b7 ".join(meta))
                out.append("")
            body = comment.body.strip()
            out.append(body if body else "_Empty comment._")
            out.append("")
            out.append("---")
            out.append("")

    events = [event for event in issue.events if event.text]
    if events:
        out.append("## Timeline")
        out.append("")
        for event in events:
            when = fmt_ts(event.created_at)
            out.append("- **%s** \u2014 %s" % (when or "unknown time", event.text))
        out.append("")
        out.append("---")
        out.append("")

    refs = [ref for ref in issue.cross_refs
            if ref.kind in ("cross-referenced", "referenced", "closed-by")]
    if refs:
        out.append("## Cross-references")
        out.append("")
        for ref in refs:
            label = ref.title or ("#%s" % ref.number if ref.number else ref.url or "reference")
            link = "[%s](%s)" % (label, ref.url) if ref.url else label
            extra = []
            if ref.state:
                extra.append("`%s`" % ref.state.lower())
            if ref.note:
                extra.append(ref.note)
            if ref.kind == "closed-by":
                extra.append("closed this issue")
            elif ref.kind == "referenced":
                extra.append("commit reference")
            if ref.actor and ref.actor.login:
                extra.append("by %s" % ref.actor.plain())
            when = fmt_ts(ref.created_at)
            if when:
                extra.append(when)
            out.append("- %s%s" % (link, " \u2014 " + " \u00b7 ".join(extra) if extra else ""))
        out.append("")
        out.append("---")
        out.append("")

    out.append("_Fetched from %s with `fetch_issue.py` on %s._"
               % (issue.url or repo_url,
                  datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")))
    out.append("")
    return "\n".join(out)


def _participants(issue: Issue) -> str:
    counts: Dict[str, int] = {}
    order: List[str] = []

    def add(actor: Optional[Actor]) -> None:
        if not actor or not actor.login:
            return
        if actor.login not in counts:
            counts[actor.login] = 0
            order.append(actor.login)
        counts[actor.login] += 1

    add(issue.author)
    for comment in issue.comments:
        add(comment.author)
    if len(order) <= 1:
        return ""
    order.sort(key=lambda login: -counts[login])
    return ", ".join("`@%s` (%d)" % (login, counts[login]) for login in order[:12])


# --------------------------------------------------------------------------- #
# Target parsing + CLI
# --------------------------------------------------------------------------- #


def parse_target(value: str, default_repo: str) -> Tuple[str, int]:
    text = (value or "").strip()
    if not text:
        raise FetchError("no issue number given")

    url_match = re.match(
        r"^(?:https?://)?(?:www\.)?github\.com/(?P<repo>[^/\s]+/[^/\s]+)/(?:issues|pull)/(?P<num>\d+)",
        text,
        re.I,
    )
    if url_match:
        return url_match.group("repo"), int(url_match.group("num"))

    repo_match = re.match(r"^(?P<repo>[^/\s#]+/[^/\s#]+)#(?P<num>\d+)$", text)
    if repo_match:
        return repo_match.group("repo"), int(repo_match.group("num"))

    number_match = re.match(r"^#?(\d+)$", text)
    if number_match:
        return default_repo, int(number_match.group(1))

    raise FetchError(
        "cannot understand %r; pass an issue number (9135), owner/repo#9135 or a full URL" % text
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fetch_issue.py",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Download a GitHub issue (title, description, comments, timeline) as Markdown.",
        epilog=(
            "examples:\n"
            "  python fetch_issue.py 9135\n"
            "  python fetch_issue.py https://github.com/microsoft/DirectXShaderCompiler/issues/9135\n"
            "  python fetch_issue.py 9135 --no-api -o issue-9135.md\n"
        ),
    )
    parser.add_argument("target", help="issue number, owner/repo#number or a GitHub issue URL")
    parser.add_argument("-r", "--repo", default=DEFAULT_REPO,
                        help="repository used when only a number is given (default: %(default)s)")
    parser.add_argument("-o", "--output", default=None,
                        help="output file (default: issue-<number>.md)")
    parser.add_argument("--token", default=None, help="GitHub token for the REST API")
    parser.add_argument("--no-api", action="store_true",
                        help="skip the REST API and scrape the public issue page")
    parser.add_argument("--json", dest="json_output", default=None, metavar="PATH",
                        help="also write the normalised data as JSON")
    parser.add_argument("--no-events", action="store_true", help="omit the timeline section")
    parser.add_argument("--all-events", action="store_true",
                        help="keep subscription/mention timeline noise")
    parser.add_argument("--max-pages", type=int, default=50,
                        help="maximum API/HTML pages to walk (default: %(default)s)")
    parser.add_argument("--timeout", type=float, default=30.0,
                        help="per-request timeout in seconds (default: %(default)s)")
    parser.add_argument("-q", "--quiet", action="store_true", help="suppress progress output")
    return parser


def issue_to_dict(issue: Issue) -> Dict:
    def actor(actor_obj: Optional[Actor]):
        if not actor_obj:
            return None
        return {"login": actor_obj.login, "url": actor_obj.url,
                "name": actor_obj.name, "bot": actor_obj.bot}

    return {
        "repo": issue.repo,
        "number": issue.number,
        "url": issue.url,
        "title": issue.title,
        "body": issue.body,
        "state": issue.state,
        "state_reason": issue.state_reason,
        "is_pull_request": issue.is_pr,
        "author": actor(issue.author),
        "created_at": issue.created_at,
        "updated_at": issue.updated_at,
        "closed_at": issue.closed_at,
        "labels": [{"name": name, "description": description}
                   for name, description in issue.labels],
        "assignees": [actor(a) for a in issue.assignees],
        "milestone": issue.milestone,
        "projects": issue.projects,
        "sub_issues": {"completed": issue.sub_issues[0], "total": issue.sub_issues[1]}
        if issue.sub_issues else None,
        "reactions": issue.reactions,
        "comment_count": issue.comment_count,
        "comments": [
            {
                "id": comment.id,
                "author": actor(comment.author),
                "body": comment.body,
                "created_at": comment.created_at,
                "updated_at": comment.updated_at,
                "url": comment.url,
                "author_association": comment.association,
                "minimized_reason": comment.minimized_reason,
                "reactions": comment.reactions,
            }
            for comment in issue.comments
        ],
        "events": [
            {"created_at": event.created_at, "text": event.text, "url": event.url}
            for event in issue.events
        ],
        "cross_references": [
            {
                "kind": ref.kind,
                "number": ref.number,
                "url": ref.url,
                "title": ref.title,
                "state": ref.state,
                "is_pull_request": ref.is_pr,
                "actor": actor(ref.actor),
                "created_at": ref.created_at,
                "note": ref.note,
            }
            for ref in issue.cross_refs
        ],
        "source": issue.source,
    }


def main(argv: Optional[List[str]] = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
        except Exception:  # pragma: no cover - very old/odd streams
            pass

    parser = build_parser()
    args = parser.parse_args(argv)
    _Quiet.quiet = bool(args.quiet)
    _Quiet.all_events = bool(args.all_events)

    try:
        repo, number = parse_target(args.target, args.repo)
        if repo.count("/") != 1:
            raise FetchError("repository must look like owner/name, got %r" % repo)
        log("Fetching %s#%d ..." % (repo, number))

        issue: Optional[Issue] = None
        if not args.no_api:
            token, origin = (args.token, "--token") if args.token else discover_token()
            if not token:
                log("No GitHub token found; trying the anonymous REST API")
            try:
                issue = fetch_via_api(repo, number, token, args.max_pages, args.timeout)
            except FetchError as exc:
                log("REST API unavailable (%s); falling back to the issue web page" % exc)
                issue = None

        if issue is None:
            issue = fetch_via_html(repo, number, args.max_pages, args.timeout)

        if args.no_events:
            issue.events = []

        markdown = render_markdown(issue)
        output_path = args.output or ("issue-%d.md" % number)
        with open(output_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(markdown)

        if args.json_output:
            with open(args.json_output, "w", encoding="utf-8", newline="\n") as handle:
                json.dump(issue_to_dict(issue), handle, indent=2, ensure_ascii=False)
                handle.write("\n")
            log("Wrote %s" % args.json_output)

        log(
            "Saved %s (%s, %d comments, %d timeline events, %d cross-references)"
            % (output_path, issue.state or "unknown state", len(issue.comments),
               len(issue.events), len(issue.cross_refs))
        )
        if not args.quiet:
            print(output_path)
        return 0
    except FetchError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
