# ETIR corpus fixtures

`comprehensive-mixed-content.docx` is a hand-crafted OOXML package that covers the feature grid from Spec 08:

- emoji, Arabic, and Hebrew glyphs in the main story
- tabs, preserved spaces, soft hyphen (U+00AD), and no-break hyphen (U+2011)
- hyperlink mix (external URL + bookmark), bookmarks, and threaded comments
- paired footnote/endnote references anchored inside the body
- nested table with merged cells
- modern (`wps:txbx`) and legacy (`v:textbox`) text boxes
- PAGE/NUMPAGES fields surfaced from header/footer parts

Recompute the manifest after touching the fixture:

```sh
shasum -a 256 tests/corpus/comprehensive-mixed-content.docx
```

Then update `tests/corpus/manifest.json` so CI/e2e checks can verify integrity.
