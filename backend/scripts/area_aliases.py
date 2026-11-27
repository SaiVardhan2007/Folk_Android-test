"""Area of stay: every spelling found in FOLK Users.venue -> one clean area name. Checked by hand against the old CRM export (2026-11-27).

canon(raw) returns (area, stay):
  area  the clean area name, or "" when the text is not an area
  stay  "With Parents" / "In Hostel" when the old form stored that answer in the area box, else ""
"""
import re

STAYS = {"with parents": "With Parents", "in hostel": "In Hostel"}

# (pattern on the lower-cased text, clean name). First match wins, so the more specific rules come first.
RULES = [
    (r"^(none|null|no|-|na|n/a|hyderabad|test hall)$", ""),  # test data, and "Hyderabad" alone says nothing
    (r"^ecil$", "ECIL"),
    (r"^aiims$", "AIIMS"),
    (r"kokapet|green space celestial", "Kokapet"),
    (r"aziz ?nagar|bangaliguda", "Aziz Nagar"),
    (r"gandipet|gandipeta", "Gandipet"),
    (r"moinabad|moinabadh|jbiet|yenkepalle", "Moinabad"),
    (r"don?th?[ao]n+(th)?[ao]?pally|dhonthanapally|donthanapally|cbit|mgit|icfai|\bibs\b|shankarpalli.*(donth|dontan)", "Donthanpally"),
    (r"shankar?pall?[iy]|eddumailaram", "Shankarpally"),
    (r"narsingi", "Narsingi"),
    (r"banjara hills", "Banjara Hills"),
    (r"^(lb|l\.b\.?) ?nagar", "LB Nagar"),
    (r"^kphb", "KPHB"),
    (r"gachibowli|vattinagulapalli", "Gachibowli"),
    (r"madhapur", "Madhapur"),
    (r"miyapur", "Miyapur"),
    (r"langar ?ho[au]?[sz]", "Langar Houz"),
    (r"sham?sabad", "Shamsabad"),
    (r"nalgonda", "Nalgonda"),
    (r"shadnagar", "Shadnagar"),
    (r"gandpali", "Gandpali"),
]
# Names that are a hostel or a college, not an area: left empty (their PG field already holds them).
NOT_AN_AREA = r"hostel|boys|denvesh|^yashoda"


def tidy(raw: str) -> str:
    s = re.sub(r"\s+", " ", raw).strip()
    s = re.sub(r",?\s*(TG|Telangana)?,?\s*India$", "", s, flags=re.I)  # "..., TG, India"
    s = re.sub(r"\s*-\s*\d{6}$", "", s)  # "- 500075"
    return s.split(",")[0].strip().title() if s else ""


def canon(raw):
    t = re.sub(r"\s+", " ", (raw or "")).strip()
    low = t.lower()
    if low in STAYS: return "", STAYS[low]
    if not low: return "", ""
    for pat, name in RULES:
        if re.search(pat, low): return name, ""
    if re.search(NOT_AN_AREA, low): return "", ""
    return tidy(t), ""
