"""Self-checks for tool/build_stations.py: `python3 -m unittest discover -s tool`."""
import unittest

from build_stations import _check_public, apply_overrides, choose_base, dedupe_by_frequency, keep_in_state, state_of, unknown_ids, validate_overrides


def station(uid, name="Rádio", url="https://a/stream"):
    return {"stationuuid": uid, "name": name, "url": url, "url_resolved": url}


class OverridesTest(unittest.TestCase):
    def test_hide_rename_stream_and_add(self):
        o = {"hide": ["b"], "rename": {"a": "Nova"}, "stream": {"c": "https://new/s"},
             "add": [{"id": "manual-x", "state": "Bahia", "name": "X", "stream": "https://x/s"},
                     {"id": "manual-y", "state": "Acre", "name": "Y", "stream": "https://y/s"}]}
        out = apply_overrides("Bahia", [station("a"), station("b"), station("c")], o)
        self.assertEqual([s["stationuuid"] for s in out], ["a", "c", "manual-x"])  # order kept, add last
        self.assertEqual(out[0]["name"], "Nova")
        self.assertEqual(out[1]["url_resolved"], "https://new/s")

    def test_input_is_not_modified(self):
        original = [station("a")]
        apply_overrides("Bahia", original, {"rename": {"a": "Nova"}})
        self.assertEqual(original[0]["name"], "Rádio")

    def test_manual_station_from_published_list_is_not_duplicated(self):
        o = {"add": [{"id": "manual-x", "state": "Bahia", "name": "X", "stream": "https://x/s"}]}
        out = apply_overrides("Bahia", [station("manual-x")], o)
        self.assertEqual([s["stationuuid"] for s in out], ["manual-x"])

    def test_valid_file_has_no_errors(self):
        self.assertEqual(validate_overrides({"hide": [], "rename": {}, "stream": {}, "add": []}), [])

    def test_invalid_entries_are_reported(self):
        errors = validate_overrides({
            "hidden": [],
            "stream": {"a": "ftp://x"},
            "add": [{"id": "x", "state": "Bahiaa", "name": "", "stream": "javascript:alert(1)"}],
        })
        joined = " | ".join(errors)
        for expected in ("unknown key", "ftp://x", "manual-", "'state'", "'name'", "'stream'"):
            self.assertIn(expected, joined)

    def test_wrong_types_are_reported_not_crashing(self):
        self.assertTrue(validate_overrides({"stream": [], "rename": [], "add": {}}))

    def test_unknown_ids_ignore_manual_ones(self):
        self.assertEqual(unknown_ids({"hide": ["gone", "manual-x"], "rename": {"a": "A"}}, {"a"}), ["gone"])


class StateTest(unittest.TestCase):
    def test_messy_labels(self):
        self.assertEqual(state_of("Sao Paulo (Brazil)"), "São Paulo")
        self.assertEqual(state_of("Curitiba Paraná"), "Paraná")
        self.assertEqual(state_of("Paraná(Brazil)"), "Paraná")
        self.assertEqual(state_of("Para"), "Pará")
        self.assertEqual(state_of("Mato Grosso do Sul"), "Mato Grosso do Sul")
        self.assertEqual(state_of("Fortaleza"), None)

    def test_other_states_are_dropped_unknown_kept(self):
        stations = [dict(station(str(i)), state=label) for i, label in
                    enumerate(["Pará", "Paraná", "Paraiba", "Belém"])]
        self.assertEqual([s["stationuuid"] for s in keep_in_state(stations, "Pará")], ["0", "3"])


class DedupeByFrequencyTest(unittest.TestCase):
    def names(self, *names):
        return [s["name"] for s in dedupe_by_frequency([{"name": n} for n in names])]

    def test_same_frequency_and_name_word_merge_keeping_first(self):
        self.assertEqual(self.names("Melodia FM 97.5", "Rádio Melodia 97,5 FM"), ["Melodia FM 97.5"])

    def test_same_frequency_other_station_stays(self):
        names = ("Rádio Seabra FM 104.9", "Rádio Novo Amanhecer 104.9 FM",
                 "Clube FM 96,5 MHz (Belo Horizonte - MG)", "Radio Boa Vista 96.5 Paracatu, MG")
        self.assertEqual(self.names(*names), list(names))

    def test_same_name_other_frequency_or_none_stays(self):
        names = ("FM O DIA 100.5", "Rádio FM O Dia 99.7 FM", "Rádio Cidade", "Rádio Cidade - drop80")
        self.assertEqual(self.names(*names), list(names))


class NetworkGuardTest(unittest.TestCase):
    def test_internal_addresses_are_refused(self):
        for url in ("http://127.0.0.1/x.png", "http://169.254.169.254/latest", "http://10.0.0.1/",
                    "http://[::1]/", "http://localhost/"):
            with self.assertRaises(ValueError, msg=url):
                _check_public(url)


class ChooseBaseTest(unittest.TestCase):
    published = [station(str(i)) for i in range(10)] + [station("manual-x")]

    def test_fresh_list_wins(self):
        fresh = [station(str(i)) for i in range(8)]
        self.assertEqual(choose_base(fresh, self.published), (fresh, True))

    def test_failed_fetch_keeps_published_without_manual(self):
        base, ok = choose_base(None, self.published)
        self.assertFalse(ok)
        self.assertEqual(len(base), 10)

    def test_list_that_shrank_below_half_keeps_published(self):
        self.assertFalse(choose_base([station("1")] * 4, self.published)[1])
        self.assertFalse(choose_base([], self.published)[1])

    def test_first_run_accepts_anything(self):
        self.assertEqual(choose_base([], []), ([], True))


if __name__ == "__main__":
    unittest.main()
