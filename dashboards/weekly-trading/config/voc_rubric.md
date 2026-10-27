# Comment coding rubric - CX tab (NPS verbatims)

You code customer survey comments. Each comment gets exactly these fields, and nothing else:
`rid` (copy it), `primary`, `secondary`, `polarity`, `actionable`, `sub_issue`.
The comment text is personal data. Never copy any of it into your answer: no names, places,
pet names, phone numbers, order numbers, dates or quotes. The sub_issue is your own generic words.

## Themes (primary = the main thing the comment is about; secondary = a second distinct topic or NONE)
- DEL_SPEED: how fast or on time delivery was. Fast, next day, on time, late, delayed, still waiting.
- DEL_EXEC: how the delivery was carried out by the carrier or driver, not its speed. Where and how
  the parcel was left (rain, sun, letterbox, driveway, thrown over a fence), wrong address or house,
  delivered to a neighbour, instructions or authority to leave ignored, no knock, gate left open,
  marked delivered but not received, parcel never arrived, delivery texts at odd hours, split delivery
  not explained, area not served, also positive delivery handling (driver careful, delivered to door).
- PACK_DAMAGE: packaging and items damaged in transit: dented cans, crushed boxes, bags opened or split,
  smell, oversized or hard-to-recycle boxes; also well packed.
- ORDER_ACCURACY: wrong item, missing items, short shipped, someone else's order; also complete and correct.
- PRICE_VALUE: price level and value, cheaper or dearer than elsewhere (vet, supermarket, competitors),
  delivery fees and free delivery threshold, price rises.
- PROMO_LOYALTY: sales, specials, discount codes and promotions, loyalty offers.
- RANGE_CHOICE: breadth of range, brands stocked or not stocked, one stop shop.
- AVAILABILITY: items in or out of stock, sold out, discontinued lines.
- PROD_QUALITY: the product itself: quality, pet likes it, as described, broken or faulty product,
  missing parts, expiry or short shelf life, freshness.
- AUTO_DELIVERY: Auto Delivery (repeat orders, subscriptions) mechanics: changing dates, pausing,
  cancelling, payment day, AD price changes, orders shipping after cancellation, convenience of AD.
- DIGITAL: website and app: ordering, checkout, payment options (PayPal, Afterpay), login, search,
  product pages and photos, reordering.
- SERVICE_CX: customer service team: reaching a person, chat, phone, email, how an issue was handled.
- RETURNS_REFUNDS: returns, refunds, credits.
- VET_PHARMA: vet, prescription and pharmacy process (scripts, approvals), not the price of medicines.
- GENERAL_POSITIVE: praise with no specific driver ("great", "easy", "love it", "no complaints").
- OTHER: no usable content, not about Pet Circle, or about the survey scale itself.

Rules:
- Pick the theme the customer spends the most words on, or the complaint if there is one.
  "Fast delivery but the box was crushed" -> primary PACK_DAMAGE, secondary DEL_SPEED.
- DEL_SPEED and DEL_EXEC are never merged: speed is when it came, execution is how it was handled.
- Pure praise that names drivers ("good prices and fast delivery") -> primary is the first named driver.
- secondary is NONE when there is only one topic. Never repeat primary as secondary.

## polarity - judged on what the customer WROTE, not on their score
- POS: only positive. NEG: only negative or a complaint. MIXED: both positive and negative content.
- A 9 or 10 that contains a complaint is MIXED or NEG. A 0 to 6 with only praise is POS.

## actionable
- Y if the comment points to something specific Pet Circle or its carrier could fix or change.
- N for praise, general dissatisfaction with no specific cause, or price-level comments with no lever.

## sub_issue
2 to 6 plain lowercase words, letters and spaces only, generic: no names, places, products, brands,
numbers or quotes. Say what happened, in the same words other comments would use, so they group.
Prefer these phrasings where they fit:
left in the rain / left in view from street / parcel thrown over fence / left at the letterbox;
delivery instructions ignored / driver did not knock / authority to leave ignored;
delivered to wrong address / delivered to a neighbour; marked delivered but missing / parcel never arrived;
arrived later than promised / delay in dispatch / delivery takes too long;
cans dented in transit / product boxes crushed in transit / bag opened in transit;
items missing from order / wrong item sent;
price rise without notice / unexpected delivery fee / subscription price increased;
cannot speak to a person / hard to reach a human;
hard to cancel auto delivery / paused order still shipped / cannot stop an order;
checkout will not complete / difficulty logging in / no afterpay at checkout;
product past expiry date / short shelf life on arrival; out of stock after order placed / lines keep getting discontinued;
fast delivery / competitive prices / easy to use website / helpful customer service / good product range.

## Output
A JSON array, one object per comment, in the order given:
`{"rid": "...", "primary": "DEL_EXEC", "secondary": "NONE", "polarity": "NEG", "actionable": "Y", "sub_issue": "left in the rain"}`
