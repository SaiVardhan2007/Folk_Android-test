"""PG / Hostel names: every spelling found in FOLK Users.pg_name -> one clean name. Checked by hand (2026-11-25).

canon(raw) returns the clean name, "" for an entry that is not a PG/hostel (area, workplace, "No", "Home", ...), or a tidied copy of the
text when no rule matches (a real name seen only once, kept as it is).
"""
import re

# (pattern on the lower-cased text, clean name). First match wins, so the more specific rules come first.
RULES = [
    # Not a PG / hostel: emptied (the person's other details are kept).
    (r"^(500075|alkapur|aziz ?nagar|bsc nursing|home|no|room|manager|working|jntu|kokapet|kkp|near jbit college|new hostel|chaithaya|ma|"
     r"goshke hrishikesh|poulomi rmc plant|sri ashapura glass|vidya jyothi inst.*|own house.*|akshaypatra)$", ""),
    (r"^(in ?campus|clg hostel)|chaitanya deemed", "College Hostel (In Campus)"),
    (r"^(cbit|mgit)|cbit.*mgit|mgit.*cbit", "CBIT-MGIT Boys Hostel"),
    (r"folk.*(gandipet)|gandipeta nivas", "FOLK Residency Gandipet"),
    (r"folk.*aziz ?nagar", "FOLK Residency Aziznagar"),
    (r"folk.*chilkur", "FOLK Residency Chilkur"),
    (r"folk nivas hkht", "FOLK Nivas HKHT"),
    (r"^folk (re[cs]iden(cy|ce)|nivas)$|hare krishna residency", "FOLK Residency"),
    (r"^(adithya|aditya)", "Adithya Men's PG"),
    (r"^an(a|aa)g?h?a .*(pg|men)|^anagha", "Anagha Men's PG"),
    (r"^(b ?s ?reddy)", "BS Reddy Boys Hostel"),
    (r"^best (co ?living|pg)", "Best Co-living"),
    (r"^(brindavan|brivandhavan|vrindavan|vridhavan|vrindawan)", "Vrindavan Men's PG"),
    (r"^bro( hood| pg)?$", "Bro Hood PG"),
    (r"^cbes", "CBES Boys Hostel"),
    (r"^(charan|cheran)", "Charan Boys Hostel"),
    (r"^chary", "Charys Boys Hostel"),
    (r"^cozy", "Cozy Men's PG"),
    (r"^deccan ?nest", "Deccan Nest PG"),
    (r"^(devansh|denvesh)", "Devansh Men's PG"),
    (r"^drr", "DRR Boys Hostel"),
    (r"^(friden|frieden)", "Frieden Co-living"),
    (r"^(gayatri|gaethiri)", "Gayatri Boys Hostel"),
    (r"^hack ?(n|and) ?sleep", "Hack N Sleep Men's PG"),
    (r"^happy home", "Happy Homes"),
    (r"^(sai )?(iconi[cz]|icon)(?! white)", "Sai Iconic Liv Men's & Co-living PG"),
    (r"jmj|jjm", "JMJ Boys Hostel"),
    (r"^jury", "Jury's Luxury Co-living & Men's PG"),
    (r"kamakshith?y?ayi", "Sri Kamakshithayi Boys Hostel"),
    (r"^krc", "KRC Boys Hostel"),
    (r"^mahadev", "Mahadev Boys Hostel"),
    (r"^(mahendra|mahindra)", "Mahendra Executive Gents PG"),
    (r"^manish", "Manish Men's PG"),
    (r"^(niat )?(mq|ma-1)", "MQ1 Boys Hostel"),
    (r"^(n[ -]?homes?'?s?|nhome|n home)", "N Homes Boys Hostel"),
    (r"^nexin", "Nexin Co-living"),
    (r"^rrr", "RRR Boys Hostel"),
    (r"^relic", "Relic Stays for Men"),
    (r"^(sai )?(castle|castel|catle) ?town|^sai castle", "Sai Castle Town Elite Men's PG"),
    (r"^(sai )?pranavi", "Sai Pranavi Co-living PG"),
    (r"^sai sanvi", "Sai Sanvi Men's PG"),
    (r"^siri", "Siri Boys Hostel"),
    (r"^sky ?line", "Skyline Serenity"),
    (r"^sms", "SMS Co-living"),
    (r"^spring stay", "Spring Stays Men's Hostel"),
    (r"^sr (cooliving|mens pg)", "SR Co-living Men's PG"),
    (r"^sr\.? ?(boys hostel)?$|^sr\.boys", "SR Boys Hostel"),
    (r"^sri balaji", "Sri Balaji Men's Deluxe Hostel"),
    (r"^(shri|sri) ?krishna|^srikrishna", "Sri Krishna Boys Hostel"),
    (r"^(sri )?(mitra|mithra|mintra)", "Sri Mithra Luxury Men's PG"),
    (r"^(sri|sree) srinivasa|^srinivasam", "Sri Srinivasa Men's PG"),
    (r"(vegamamba|venkamamba|vengamamba)", "Sri Vengamamba Boys Hostel"),
    (r"^(sri|shri|shi) venkatesh?w?ara|^sri venkateswara", "Sri Venkateswara Men's PG"),
    (r"^(sri )?virup", "Sri Virupaksha Men's PG"),
    (r"stanza|staxa", "Stanza Living"),
    (r"^svm grand", "SVM Grand"),
    (r"^svn ?7 ?hills", "SVN 7 Hills Men's Luxury PG"),
    (r"^trr", "TRR Boys Hostel"),
    (r"^tulip", "Tulip Nest Hostel"),
    (r"^urban stays", "Urban Stays Men's PG"),
    (r"^v (r )?grand", "V Grand White House PG"),
    (r"^white ?(house|elite)", "White House Elite Men's PG"),
    (r"^vivekanandh?a", "Vivekananda Boys Hostel"),
    (r"^vk\b", "VK Men's PG"),
    (r"^vmr", "VMR Boys Hostel"),
    (r"^ya?s?h?odha girls", "Yashoda Girls Hostel"),
    (r"^(yashoda|yashodha|yasodha|yeshoda)", "Yashoda Boys Hostel"),
    (r"^y\.? ?p\.? ?reddy", "YP Reddy Boys Hostel"),
    (r"^(yvr|y v r)", "YVR Luxury Boys PG"),
    (r"^zenvibes", "Zenvibes"),
    (r"^zion", "Zion Boys Hostel"),
    (r"^(rao'?s|roas)", "Rao's Hostel"),
    (r"^sln", "SLN Grand Men's PG"),
]
_RULES = [(re.compile(p), t) for p, t in RULES]


def tidy(s):
    s = re.sub(r"\s+", " ", s.replace("’", "'")).strip(" .,")
    return s if any(c.isupper() for c in s) else s.title()  # keep "SMS PG"; "sri maruthi" -> "Sri Maruthi"


def canon(raw):
    s = re.sub(r"\s+", " ", (raw or "").replace("’", "'")).strip()
    if not s: return ""
    low = s.lower()
    for rx, title in _RULES:
        if rx.search(low): return title
    return tidy(s)
