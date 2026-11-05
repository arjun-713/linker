"""Unit tests for the linker tool's pure logic (no filesystem side effects)."""

import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
import pathlib
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

_module_path = pathlib.Path(__file__).resolve().parent.parent / "linker"
_spec = importlib.util.spec_from_loader(
    "linker", SourceFileLoader("linker", str(_module_path))
)
linker = importlib.util.module_from_spec(_spec)
sys.modules["linker"] = linker  # required before exec for dataclass processing
_spec.loader.exec_module(linker)


class ValidationTests(unittest.TestCase):
    def test_normalize_alias_accepts_valid(self):
        self.assertEqual(linker.normalize_alias("  GitHub "), "github")
        self.assertEqual(linker.normalize_alias("my_page-2"), "my_page-2")

    def test_normalize_alias_rejects_invalid(self):
        for bad in ("", "-x", "a b", "has.dot", "a" * 33):
            with self.assertRaises(linker.LinkerError, msg=bad):
                linker.normalize_alias(bad)

    def test_clean_url_scheme(self):
        url = " https://github.com/a "
        self.assertEqual(linker.clean_url(url), url.strip())

    def test_clean_url_git_ssh_conversion(self):
        self.assertEqual(
            linker.clean_url("git@github.com:user/repo.git"),
            "https://github.com/user/repo",
        )

    def test_clean_url_rejects_bare_domain(self):
        with self.assertRaises(linker.LinkerError):
            linker.clean_url("github.com/x")

    def test_parse_tags(self):
        self.assertEqual(linker.parse_tags(" Dev, dev, ev-Work ,,x"), ["dev", "ev-work", "x"])
        self.assertEqual(linker.parse_tags(None), [])
        self.assertEqual(linker.parse_tags(""), [])


class FuzzyTests(unittest.TestCase):
    def setUp(self):
        store = linker.Store(path=":memory:")
        for alias in ("github", "gitlab", "linkedin", "resume"):
            store.add(linker.Link.new(alias, f"https://x.com/{alias}", [], ""))
        self.store = store

    def test_subsequence_scores(self):
        self.assertGreater(linker.fuzzy_score("gh", "github") or -1, 0)
        self.assertGreaterEqual(linker.fuzzy_score("github", "github"), 10)

    def test_non_match_is_none(self):
        self.assertIsNone(linker.fuzzy_score("ghz", "github"))

    def test_prefix_reward_beats_midword(self):
        self.assertGreater(
            linker.fuzzy_score("gh", "github"), linker.fuzzy_score("hu", "github")
        )

    def test_resolve_exact_and_prefix(self):
        self.assertEqual(linker.resolve(self.store, "GitHub").alias, "github")
        # "gi" and "git" are ambiguous (github, gitlab)
        for q in ("gi", "git"):
            with self.assertRaises(linker.AliasError, msg=q):
                linker.resolve(self.store, q)
        self.assertEqual(linker.resolve(self.store, "l").alias, "linkedin")

    def test_resolve_suggestions(self):
        with self.assertRaises(linker.AliasError) as ctx:
            linker.resolve(self.store, "gtihub")  # typo, caught by edit distance
        self.assertIn("github", " ".join(ctx.exception.hints))
        self.assertEqual(ctx.exception.code, 2)


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.tmp.name) / "links.json"

    def tearDown(self):
        self.tmp.cleanup()

    def mk_store(self):
        store = linker.Store(path=str(self.path))
        store.load()
        return store

    def test_roundtrip_sorted_and_unique(self):
        store = self.mk_store()
        store.add(linker.Link.new("zeta", "https://z.io", ["t"], "note"))
        store.add(linker.Link.new("alpha", "https://a.io", [], ""))
        store.save()
        reloaded = self.mk_store()
        self.assertEqual(reloaded.aliases(), ["alpha", "zeta"])
        self.assertEqual(reloaded.get("zeta").note, "note")
        self.assertEqual(reloaded.get("zeta").copy_count, 0)

    def test_stats_survive_upsert(self):
        store = self.mk_store()
        link = linker.Link.new("alpha", "https://a.io", [], "")
        link.touch_copy()
        store.add(link)
        store.save()
        reloaded = self.mk_store()
        imported = linker.Link.from_dict(
            {"alias": "alpha", "url": "https://a.io/v2", "tags": ["t"]}
        )
        reloaded.upsert(imported)
        kept = reloaded.get("alpha")
        self.assertEqual(kept.url, "https://a.io/v2")
        self.assertEqual(kept.copy_count, 1)  # stats preserved on update
        self.assertTrue(kept.created_at)      # created_at preserved on update

    def test_upsert_backfills_missing_timestamps(self):
        store = self.mk_store()
        imported = linker.Link.from_dict({"alias": "new", "url": "https://n.io"})
        before = datetime.now(timezone.utc)
        store.upsert(imported)
        after = datetime.now(timezone.utc)
        created = datetime.fromisoformat(store.get("new").created_at)
        # isoformat strips microseconds, so compare against the floored second
        self.assertTrue(before.replace(microsecond=0) <= created <= after)

    def test_broken_file_quarantined(self):
        self.path.write_text("{not json")
        store = self.mk_store()
        self.assertEqual(store.aliases(), [])
        quarantined = list(self.path.parent.glob("links.json.broken-*"))
        self.assertEqual(len(quarantined), 1)

    def test_save_is_atomic_and_private(self):
        store = self.mk_store()
        store.add(linker.Link.new("a", "https://a.io", [], ""))
        store.save()
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        payload = json.loads(self.path.read_text())
        self.assertEqual(payload["version"], 1)


class PlatformTests(unittest.TestCase):
    """macOS/Linux behavior switches (pbcopy vs wl-copy, open vs xdg-open)."""

    def setUp(self):
        self.was_macos = linker.IS_MACOS

    def tearDown(self):
        linker.IS_MACOS = self.was_macos

    def test_clipboard_override_takes_precedence(self):
        old = os.environ.get("LINKER_CLIPBOARD")
        os.environ["LINKER_CLIPBOARD"] = "mytool"
        try:
            self.assertEqual(linker.clipboard_candidates(), [("mytool", "arg")])
        finally:
            if old is None:
                del os.environ["LINKER_CLIPBOARD"]
            else:
                os.environ["LINKER_CLIPBOARD"] = old

    def test_macos_chain_is_pbcopy_and_open(self):
        linker.IS_MACOS = True
        self.assertEqual(linker.clipboard_candidates(), [("pbcopy", "stdin")])
        self.assertEqual(linker.default_opener(), "open")

    def test_linux_chain_has_wl_and_xdgo(self):
        linker.IS_MACOS = False
        names = [name for name, _ in linker.clipboard_candidates()]
        self.assertIn("wl-copy", names)
        self.assertEqual(linker.default_opener(), "xdg-open")


class TimeTests(unittest.TestCase):
    def test_relative_labels(self):
        now = datetime.now(timezone.utc).isoformat(timespec="seconds")
        self.assertEqual(linker.time_ago(now), "just now")
        self.assertEqual(linker.time_ago(""), "never")
        old = (datetime.now(timezone.utc) - timedelta(hours=30)).isoformat()
        self.assertEqual(linker.time_ago(old), "1d ago")
        older = (datetime.now(timezone.utc) - timedelta(days=45)).isoformat()
        self.assertEqual(linker.time_ago(older), datetime.fromisoformat(older).strftime("%Y-%m-%d"))


if __name__ == "__main__":
    unittest.main()
