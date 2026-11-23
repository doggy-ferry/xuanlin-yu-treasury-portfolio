"""Browser checks at 390/430/768/1440 px. Uses a locally installed Chromium-based browser via
Playwright (no download). Skipped, not failed, when no browser can be launched."""

import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

pw = pytest.importorskip("playwright.sync_api")
ROOT = Path(__file__).resolve().parents[1]
WIDTHS = [(390, 844), (430, 932), (768, 1024), (1440, 900)]


def _free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
def server(tmp_path_factory):
    port = _free_port()
    env = {**os.environ, "PJ6_RUNTIME_DIR": str(tmp_path_factory.mktemp("rt"))}
    for k in ("ANTHROPIC_API_KEY", "ANTHROPIC_MODEL"):
        env.pop(k, None)
    proc = subprocess.Popen([sys.executable, "-m", "uvicorn", "app.main:app", "--port", str(port)], cwd=ROOT, env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    url = f"http://127.0.0.1:{port}"
    for _ in range(60):
        try:
            urllib.request.urlopen(url + "/api/health", timeout=1)
            break
        except Exception:
            time.sleep(0.25)
    yield url
    proc.terminate()


@pytest.fixture(scope="module")
def browser():
    with pw.sync_playwright() as p:
        b = None
        for kw in ({"channel": "msedge"}, {"channel": "chrome"}, {}):
            try:
                b = p.chromium.launch(headless=True, **kw)
                break
            except Exception:
                continue
        if b is None:
            pytest.skip("no Chromium-based browser available for Playwright")
        yield b
        b.close()


def page_json(server, path):
    return json.loads(urllib.request.urlopen(server + path).read())


def open_view(browser, server, w, h, view):
    page = browser.new_page(viewport={"width": w, "height": h})
    page.goto(server)
    page.wait_for_selector(".tab")
    if view == "queue":
        page.click('[data-view="queue"]')
        page.wait_for_selector("#rows tr")
    elif view == "evaluation":
        page.click('[data-view="evaluation"]')
        page.wait_for_selector(".matrix")
    elif view == "detail":
        page.click('[data-view="queue"]')
        page.wait_for_selector("#rows tr")
        page.click("[data-open='INV-0001']")
        page.wait_for_selector("[data-act]")
    else:
        page.wait_for_selector(".kpi")
    return page


@pytest.mark.parametrize("w,h", WIDTHS)
@pytest.mark.parametrize("view", ["overview", "queue", "detail", "evaluation"])
def test_no_horizontal_overflow(browser, server, w, h, view):
    page = open_view(browser, server, w, h, view)
    sw = page.evaluate("document.documentElement.scrollWidth")
    assert sw <= w, f"{view}@{w}: scrollWidth {sw}"
    page.close()


@pytest.mark.parametrize("w,h", WIDTHS)
@pytest.mark.parametrize("view", ["overview", "queue", "detail", "evaluation"])
def test_touch_targets_at_least_44px(browser, server, w, h, view):
    page = open_view(browser, server, w, h, view)
    small = page.evaluate("""() => [...document.querySelectorAll('button, select, input[type=search], textarea, label.check')]
        .filter(e => e.offsetParent !== null).map(e => [e.tagName + ' ' + (e.textContent||e.id).trim().slice(0,24), e.getBoundingClientRect().height])
        .filter(([n, hgt]) => hgt < 43.5)""")
    assert small == [], f"{view}@{w}: {small}"
    page.close()


def test_table_becomes_cards_on_phone_and_stays_table_on_desktop(browser, server):
    phone = open_view(browser, server, 390, 844, "queue")
    assert phone.evaluate("getComputedStyle(document.querySelector('#rows tr')).display") == "block"
    assert phone.evaluate("document.documentElement.scrollWidth") <= 390
    phone.close()
    desk = open_view(browser, server, 1440, 900, "queue")
    assert desk.evaluate("getComputedStyle(document.querySelector('#rows tr')).display") == "table-row"
    desk.close()


def test_reason_codes_are_separated_and_never_split_mid_word(browser, server):
    page = open_view(browser, server, 1440, 900, "queue")
    ok = page.evaluate("""() => [...document.querySelectorAll('td[data-label="Reason codes"] .codes')].every(c => {
        const chips = [...c.querySelectorAll('.chip')];
        return chips.length < 2 || /\\s/.test(c.textContent.trim());
    })""")
    assert ok
    assert page.locator(".codes .chip").count() > 0
    # no chip may wrap onto several lines on desktop (that would split a code mid-word)
    assert page.evaluate("""() => [...document.querySelectorAll('.codes .chip')].every(c => c.getClientRects().length === 1 && c.getBoundingClientRect().height < 30)""")
    page.close()


def test_review_mode_does_not_show_ground_truth(browser, server):
    for view in ("queue", "detail"):
        page = open_view(browser, server, 1440, 900, view)
        text = page.inner_text("main").lower()
        for banned in ("ground_truth", "actually exception", "false negative", "false positive", "anomaly_type"):
            assert banned not in text, (view, banned)
        assert "ground truth hidden" in text or "ground truth is hidden" in text
        page.close()


def test_filters_and_detail_actions_work_in_browser(browser, server):
    flagged = [v["invoice_id"] for v in page_json(server, "/api/invoices") if v["in_queue"]]
    q, qid = len(flagged), flagged[0]
    page = open_view(browser, server, 1440, 900, "queue")
    page.select_option("#f-status", "auto")
    assert page.inner_text("#count").startswith(f"{100 - q} of 100")
    page.select_option("#f-status", "flagged")
    assert page.inner_text("#count").startswith(f"{q} of 100")
    page.check("#f-pending")
    page.fill("#f-q", qid)
    assert page.inner_text("#count").startswith("1 of 100")
    page.click(f"[data-open='{qid}']")
    page.fill("#note", "browser test note")
    page.click("[data-act='escalate']")
    page.wait_for_selector(".history li")
    assert "Escalated" in page.inner_text(".history")
    page.request.post(server + "/api/reviews/reset")
    page.close()


def test_static_snapshot_mode_works_without_backend(browser, server, tmp_path):
    """Serve only the static folder (no /api) and make sure the demo still renders."""
    port = _free_port()
    proc = subprocess.Popen([sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"],
                            cwd=ROOT / "frontend", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1)
        page = browser.new_page(viewport={"width": 1440, "height": 900})
        page.goto(f"http://127.0.0.1:{port}/")
        page.wait_for_selector(".kpi")
        assert "static" in page.inner_text("#mode-pill").lower()
        assert "Live API mode" in page.inner_text("#modeline")
        page.click('[data-view="queue"]')
        page.wait_for_selector("#rows tr")
        assert page.inner_text("#count").startswith("100 of 100")
        page.close()
    finally:
        proc.terminate()



