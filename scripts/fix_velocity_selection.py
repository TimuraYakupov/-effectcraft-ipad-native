"""Fix Keyframe Velocity eligibility for *all* selected keys, not just the first.

The upstream v0.17 dialog queries keys.info but incorrectly takes has_in/has_out
from the first selected key. A selected first key has no incoming handle,
so Incoming becomes disabled for all selected keys. Apply a narrow, testable
frontend change without altering the shared keyframe engine or selection model.
"""
from pathlib import Path
import sys

def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"Expected exactly one occurrence of {old[:65]!r}; found {text.count(old)}")
    return text.replace(old, new)

def main(root: Path) -> None:
    path = root / "crates/ui-egui/src/panels/key_dialogs.rs"
    text = path.read_text(encoding="utf-8")
    anchor = '/// Animation ▸ Keyframe Velocity… (⇧⌘K) with keys selected.\n'
    helper = '''/// Find a real handle on this side among *all* selected keyframes.
///
/// The first selected key may be an endpoint (and have no incoming handle);
/// that must not disable incoming editing for the interior selected keys.
fn first_eligible_ease<'a>(selected: &'a [Value], side: &str) -> Option<&'a [Value]> {
    selected
        .iter()
        .filter_map(|key| key.get(side).and_then(Value::as_array))
        .find(|ease| ease.iter().any(|entry| !entry.is_null()))
        .map(Vec::as_slice)
}

'''
    text = replace_once(text, anchor, helper + anchor)
    text = replace_once(text,
'''    let first = info.as_array().and_then(|a| a.first()).ok_or("select keyframes first")?;
''',
'''    let selected = info.as_array().ok_or("select keyframes first")?;
    let first = selected.first().ok_or("select keyframes first")?;
''')
    text = replace_once(text,
'''        let a = first[k].as_array().cloned().unwrap_or_default();
        let has = a.iter().any(|e| !e.is_null());
''',
'''        let a = first_eligible_ease(selected, k).unwrap_or_default();
        let has = !a.is_empty();
''')
    tests = '''
#[cfg(test)]
mod velocity_multiselection_tests {
    use super::first_eligible_ease;
    use serde_json::json;

    #[test]
    fn endpoint_first_still_allows_editing_both_sides_of_selected_keys() {
        let keys = json!([
            {"inEase": [null], "outEase": [{"speed": 2.0, "influence": 55.0}]},
            {"inEase": [{"speed": 3.0, "influence": 45.0}], "outEase": [null]}
        ]);
        let selected = keys.as_array().unwrap();
        assert_eq!(first_eligible_ease(selected, "inEase").unwrap()[0]["speed"], 3.0);
        assert_eq!(first_eligible_ease(selected, "outEase").unwrap()[0]["speed"], 2.0);
    }

    #[test]
    fn unavailable_side_remains_disabled_for_single_endpoint() {
        let keys = json!([
            {"inEase": [null], "outEase": [{"speed": 2.0, "influence": 55.0}]}
        ]);
        let selected = keys.as_array().unwrap();
        assert!(first_eligible_ease(selected, "inEase").is_none());
        assert!(first_eligible_ease(selected, "outEase").is_some());
    }

    #[test]
    fn empty_and_multiple_dimensions_are_handled() {
        let empty = json!([]);
        assert!(first_eligible_ease(empty.as_array().unwrap(), "outEase").is_none());
        let selected = json!([
            {"inEase": [null, null]},
            {"inEase": [{"speed": 6.0}, {"speed": 8.0}]}
        ]);
        assert_eq!(first_eligible_ease(selected.as_array().unwrap(), "inEase").unwrap().len(), 2);
    }
}
'''
    if "mod velocity_multiselection_tests" in text:
        raise RuntimeError("Velocity fix already applied")
    path.write_text(text.rstrip() + "\n" + tests, encoding="utf-8")
    print(f"Applied multi-selection Keyframe Velocity fix: {path}", flush=True)

if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
