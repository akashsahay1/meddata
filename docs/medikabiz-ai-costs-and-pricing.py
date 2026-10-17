# Builds docs/medikabiz-ai-costs-and-pricing.pdf (needs reportlab): python3 docs/medikabiz-ai-costs-and-pricing.py docs/medikabiz-ai-costs-and-pricing.pdf
import sys
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, KeepTogether

from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.fonts import addMapping

OUT = sys.argv[1]
FONTS = '/Volumes/Projects/Projects/meddata/app/assets/fonts/pdf/'   # the app's own PDF font (has ₹)
pdfmetrics.registerFont(TTFont('GS', FONTS + 'GoogleSansFlex-Regular.ttf'))
pdfmetrics.registerFont(TTFont('GS-Bold', FONTS + 'GoogleSansFlex-Bold.ttf'))
for b in (0, 1):
    for i in (0, 1):
        addMapping('GS', b, i, 'GS-Bold' if b else 'GS')
INR = 88            # rupees per US dollar (assumption)
TAX = 1.18 * 1.035  # 18% GST on imported services (reverse charge) + ~3.5% card forex fee
RETRY = 1.25        # re-reads after a bad reply or a busy service

# Measured on the sample invoices, 17 Oct 2026 (tokens).
TEXT = dict(model='openai/gpt-oss-120b', inp=0.15, out=0.60)   # $ per million tokens
VISION = dict(model='qwen/qwen3.8-27b', inp=0.80, out=4.00)
def cost(m, i, o): return (i * m['inp'] + o * m['out']) / 1e6
PER = {   # (lines, text-PDF $, photo $) for one read
    10: (cost(TEXT, 1950, 2197), cost(VISION, 1800, 1400)),
    20: (cost(TEXT, 2500, 3300), cost(VISION, 2500, 2900)),
    48: (cost(TEXT, 3799, 7588), cost(VISION, 4000, 6800)),
}
t20, p20 = PER[20]
MIX = (t20 + p20) / 2 * RETRY          # typical invoice, half PDFs half photos
PHOTO = p20 * RETRY                    # all photos
TOKENS = 7000                          # tokens per invoice incl. re-reads (both models similar)
rs = lambda usd: usd * INR             # before tax
rst = lambda usd: usd * INR * TAX      # what it really costs, with GST and forex

SMALL, MEDIUM = 50, 150                # invoices a month
AVG = 0.625 * SMALL + 0.375 * MEDIUM   # 250 small + 150 medium out of 400

ss = getSampleStyleSheet()
H1 = ParagraphStyle('h1', parent=ss['Title'], fontName='GS-Bold', fontSize=19, leading=23, spaceAfter=2, alignment=0, textColor=colors.HexColor('#0f3d5c'))
H2 = ParagraphStyle('h2', parent=ss['Heading2'], fontName='GS-Bold', fontSize=13, leading=16, spaceBefore=10, spaceAfter=4, textColor=colors.HexColor('#0f3d5c'))
B = ParagraphStyle('b', parent=ss['BodyText'], fontName='GS', fontSize=9.5, leading=13)
S = ParagraphStyle('s', parent=B, fontSize=8, leading=10.5, textColor=colors.HexColor('#444444'))
BOX = ParagraphStyle('box', parent=B, backColor=colors.HexColor('#fff4e5'), borderColor=colors.HexColor('#e0a050'),
                     borderWidth=0.6, borderPadding=7, spaceBefore=6, spaceAfter=10)
P = lambda t, st=B: Paragraph(t, st)

def table(rows, widths, bold_last=False):
    t = Table([[P(str(c), S if r else ParagraphStyle('th', parent=S, fontName='GS-Bold', textColor=colors.white))
                for c in row] for r, row in enumerate(rows)], colWidths=[w * mm for w in widths], repeatRows=1)
    st = [('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0f3d5c')), ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#bbbbbb')),
          ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'), ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#f3f6f8')])]
    if bold_last: st.append(('BACKGROUND', (0, -1), (-1, -1), colors.HexColor('#e3eef5')))
    t.setStyle(TableStyle(st))
    return t

r0 = lambda x: f"₹{x:,.0f}"
r2 = lambda x: f"₹{x:,.2f}"
d4 = lambda x: f"${x:.4f}"

story = [P("Medikabiz: AI bill reading", H1),
         P("Cost, limits and how to charge shops &nbsp;·&nbsp; prepared 17 October 2026 for Alok ji", S), Spacer(1, 8)]

story += [P("Summary", H2), P(
    f"<b>1.</b> Reading one supplier bill with AI costs about <b>{r2(rst(MIX))}</b> on average (half PDFs, half photos, "
    f"with GST and card fees). A PDF made by billing software costs about {r2(rst(t20 * RETRY))}; a photo about {r2(rst(PHOTO))}.<br/>"
    f"<b>2.</b> A small shop (~{SMALL} bills a month) costs about <b>{r0(rst(MIX) * SMALL)}</b> a month; a medium shop "
    f"(~{MEDIUM} bills) about <b>{r0(rst(MIX) * MEDIUM)}</b>. For 400 shops: about <b>{r0(rst(MIX) * AVG * 400)}</b> a month.<br/>"
    "<b>3.</b> Money is not the main risk; <b>Groq's usage limits are</b>. The free key we use today is enough for only about 15 shops. "
    "Upgrade to the Developer plan before launch and check the limits in the table in section 5.<br/>"
    "<b>4.</b> The current plans (₹99 a month, ₹999 a year, ₹2,499 lifetime) cannot include unlimited AI reading: a medium "
    "shop's AI cost alone is more than the monthly plan. Include a small monthly allowance and sell scan packs (section 7).", B)]

story += [P("1. How Groq charges", H2), P(
    "Groq charges per <b>token</b> (a token is about ¾ of a word; a picture is converted into tokens too). There is no monthly fee "
    "and no prepaid balance: usage is billed to a card afterwards. For an Indian billing address the card is charged when usage reaches "
    "$1, then $10, then every $100 (about ₹8,800 each time). Below $0.50 nothing is charged.", B),
    table([["What is read", "Groq model", "Per million input tokens", "Per million output tokens"],
           ["PDF with text inside (made by billing software)", TEXT['model'], f"${TEXT['inp']:.2f}", f"${TEXT['out']:.2f}"],
           ["Photo, or a PDF that is only a scanned photo", VISION['model'], f"${VISION['inp']:.2f}", f"${VISION['out']:.2f}"]],
          [62, 38, 38, 38]),
    Spacer(1, 4), P("Groq's Batch service is 50% cheaper and does not count against the limits, but results can take up to 24 hours "
                    "(useful for overnight reading).", S)]

story += [P("2. Cost of reading one bill (measured)", H2), P(
    "Measured on sample bills on 17 Oct 2026. In rupees at ₹88 per dollar, before GST; the last column adds 18% GST and the card's "
    "foreign-exchange fee.", B),
    table([["Bill", "PDF with text", "Photo / scan", "Photo, with GST + fees"]] +
          [[f"{n} lines" + (" (2 pages)" if n == 48 else " (typical)" if n == 20 else ""), f"{d4(t)} = {r2(rs(t))}", f"{d4(p)} = {r2(rs(p))}", r2(rst(p))]
           for n, (t, p) in PER.items()], [40, 45, 45, 45]),
    P(f"Average used below: a 20-line bill, half PDFs and half photos, plus 25% for re-reads = <b>${MIX:.4f} = {r2(rs(MIX))}</b> "
      f"before tax, <b>{r2(rst(MIX))}</b> with GST and fees.", B)]

rows = [["Shop", "Bills a month", "AI cost a month (with GST + fees)", "Cost per bill"]]
for name, n, per in [("Small", SMALL, MIX), ("Medium", MEDIUM, MIX), ("Busy, all photos", 200, PHOTO)]:
    rows.append([name, n, r0(rst(per) * n), r2(rst(per))])
story += [P("3. Monthly cost per shop", H2), table(rows, [50, 30, 60, 35])]

rows = [["Shops", "Bills a month", "Groq bill (before tax)", "Real cost (GST + fees)"]]
for shops in (20, 50, 100, 200, 400):
    bills = shops * AVG
    rows.append([shops, f"{bills:,.0f}", f"${MIX * bills:,.0f} = {r0(rs(MIX * bills))}", r0(rst(MIX * bills))])
story += [P("4. Monthly cost for all shops", H2),
          P(f"Mix assumed: 5 small shops for every 3 medium ones (an average of {AVG:.0f} bills per shop a month).", B),
          table(rows, [25, 35, 55, 55], bold_last=True)]

rows = [["Shops", "Bills a day", "Tokens a day", "Busiest minute (tokens)", "Free key today"]]
for shops in (20, 50, 100, 200, 400):
    day = shops * AVG / 30
    rows.append([shops, f"{day:,.0f}", f"{day * TOKENS / 1e6:,.1f} million", f"{day * 0.2 / 60 * 3 * TOKENS:,.0f}",
                 "OK" if day * TOKENS / 2 <= 200_000 else "Not enough"])
story += [KeepTogether([P("5. Groq limits: will it keep working?", H2), P(
    "Groq limits how much one account may use <b>per minute and per day</b>, for each model separately. When a limit is reached, "
    "requests are refused until the minute or day resets. The free key we use now allows about <b>8,000 tokens a minute and "
    "200,000 a day per model</b>, which is about 28 bills a day per model, enough for only about 15 shops.", B),
    P(f"A bill uses about {TOKENS:,} tokens including re-reads. 'Busiest minute' assumes a fifth of the day's bills arrive in the "
      "busiest hour, and three times that for shops uploading several bills at once.", S), table(rows, [18, 25, 33, 42, 30])])]
story += [P(
    "<b>What to do before launch:</b> (1) upgrade the Groq account to the <b>Developer plan</b>; (2) open console.groq.com, Settings &gt; "
    "Limits and check each model allows at least <b>60,000 tokens a minute and 10 million tokens a day</b> (enough for 400 shops with "
    "room to spare); (3) if not, ask Groq support for a production limit increase before onboarding many shops. "
    "The app will queue bills and wait out short limits by itself, so a busy minute shows 'Trying again…' instead of an error, "
    "but a daily limit would make bills wait until the next day.", BOX)]
story += [P("Important: Groq lists the photo model (qwen3.8-27b) as a <b>preview</b> model, 'for evaluation only', which Groq can "
            "withdraw at short notice. The PDF model (gpt-oss-120b) is a production model. We should keep a second provider ready "
            "for photos (for example Claude or Gemini), and encourage shops to upload PDFs, which are also 5–6 times cheaper and exact.", B)]

rows = [["Stage", "Expected Groq bill a month", "Spend limit to set", "Email alerts at"]]
for name, shops in (("Pilot", 20), ("Launch", 100), ("Growth", 200), ("Full", 400)):
    exp = MIX * shops * AVG
    lim = max(50, int(-(-exp * 2.5 // 50) * 50))
    rows.append([f"{name} ({shops} shops)", f"${exp:,.0f} = {r0(rs(exp))}", f"${lim:,} = {r0(lim * INR)}", "50%, 75%, 90%"])
story += [KeepTogether([P("6. How much to budget on Groq", H2), P(
    "Groq does not take money in advance, so there is nothing to 'add' up front. Instead, set a <b>monthly spend limit</b> "
    "(in the Groq console: Settings, Billing, Limits) as a safety cap, with email alerts. When the cap is reached Groq <b>blocks all reading until the 1st "
    "of next month</b>, so the cap must be well above normal use: we suggest 2.5 times the expected bill.", B),
    table(rows, [45, 45, 45, 35]),
    P("Use a card enabled for <b>international, recurring</b> payments. Indian cards may refuse automatic foreign charges; Groq's "
      "charges of about ₹8,800 each stay under the ₹15,000 limit for automatic recurring debits, but the card must allow e-mandates.", B)])]

story += [P("7. How to charge shops", H2), P(
    "Current plans: Monthly ₹99, Yearly ₹999 (₹83 a month), Lifetime ₹2,499 once. A medium shop's AI reading costs about "
    f"{r0(rst(MIX) * MEDIUM)} a month, more than the whole monthly plan, and a lifetime plan with unlimited AI would lose money every month, forever.", B),
    table([["Proposal", "Price", "Our AI cost (worst case: all photos)", "Why"],
           ["Included in Monthly / Yearly", "20 bills a month", r0(rst(PHOTO) * 20), "Every shop tries it and sees the value; costs at most a third of ₹99"],
           ["Lifetime plan", "20 bills a month for the first year, then packs", "-", "A one-time price cannot pay for AI every month"],
           ["Scan pack: 100 bills", "₹199", r0(rst(PHOTO) * 100), "Covers even all-photo shops; good margin on PDFs"],
           ["Scan pack: 300 bills", "₹499", r0(rst(PHOTO) * 300), "For busy shops; works out to ₹1.66 a bill"],
           ["Or: AI plan add-on", "₹199 a month, up to 150 bills", r0(rst(PHOTO) * 150), "Simple for medium shops; fair-use limit protects us"]],
          [42, 38, 35, 60]),
    P("In the app: show <b>'Bills left this month'</b> on the scan screen, warn at 80%, and when the allowance is used up, offer a pack "
      "or typing the bill by hand, never a sudden error at the counter. Count every bill as one, whether PDF or photo, to keep it simple; "
      "PDFs are the cheap case and give the margin.", B)]

story += [P("8. Assumptions", H2), P(
    f"Prices from Groq's model page on 17 Oct 2026; token counts measured on sample bills the same day. ₹{INR} per dollar. "
    "18% GST on imported services under reverse charge (ask the CA) and about 3.5% card foreign-exchange fee. "
    f"{SMALL} bills a month for a small shop and {MEDIUM} for a medium one, 20 lines each, half PDFs and half photos, "
    "25% extra for re-reads. Real shops will differ: the Groq console shows actual usage, and we should check these numbers after the "
    "first month of the pilot.", S)]

doc = SimpleDocTemplate(OUT, pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm, topMargin=14 * mm, bottomMargin=14 * mm,
                        title="Medikabiz: AI bill reading costs and pricing", author="Medikabiz")
doc.build(story, onFirstPage=lambda c, d: None,
          onLaterPages=lambda c, d: (c.setFont('GS', 7.5), c.drawRightString(A4[0] - 16 * mm, 8 * mm, f"Medikabiz · AI bill reading · page {d.page}")))
print(f"MIX ${MIX:.4f} = Rs{rst(MIX):.2f}; PHOTO Rs{rst(PHOTO):.2f}; 400 shops Rs{rst(MIX) * AVG * 400:,.0f}")
