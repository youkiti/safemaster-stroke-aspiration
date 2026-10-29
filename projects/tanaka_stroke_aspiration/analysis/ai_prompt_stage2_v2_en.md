This is an English translation for readers. The Japanese original (ai_prompt_stage2_v2.md) was the prompt actually used.

# Instructions for stage 2 AI draft classification (classification criteria v2)

You are a reviewer reading medical safety incident reports from Japan's Project to Collect Medical Near-Miss/Adverse Event Information and classifying aspiration and choking incidents related to food or fluid intake in patients with stroke. For each input case, select values for the following 11 items according to the criteria and quote the supporting original text verbatim.

## Input

Each JSONL line represents one case. Keys are column names: case ID（事例ID）, directly related disease（直接関連する疾患名）, related diseases（関連する疾患名）, incident time band（発生時間帯）, procedure type（種類）, patient state immediately before the incident（直前の患者の状態）, involved staff（当事者）, purpose of care（医療行為の目的）, incident description（事例の内容）, background factors（背景要因）, improvement measures（改善策）, etc. The narrative comprises the incident description, background factors and improvement measures; the other fields appear above the case narrative.

## Information permitted for classification

In addition to the narrative, the fields (directly related disease, related diseases, incident time band, purpose of care, patient state immediately before the incident, involved staff, etc.) may be used as evidence. Minimise unknown values where possible and classify items that can reasonably be determined from the recorded information. However, do not infer anything that an item's criteria explicitly prohibit inferring.

## Items and classification criteria (use the option strings exactly as written)

### Role of stroke（脳卒中の位置づけ）
- Main condition or sequelae under management（主病態・管理中の後遺症）: the main condition for the admission, or stroke sequelae being managed during the admission. Select this when the directly related disease is stroke (including cerebral infarction, cerebral haemorrhage or sequelae).
- Comorbidity or history（併存・既往）: admission for another disease, with stroke recorded as a comorbidity or past history. Select this when the directly related disease is a disease other than stroke and stroke appears only in related diseases or the history in the narrative.
- If the directly related disease names the incident itself, such as aspiration or choking, use the related diseases and narrative to decide whether the main condition managed during admission was stroke (including sequelae).
- Indeterminable（判定不能）: the fields and narrative together do not establish whether stroke was the main condition or a comorbidity or history.

### Stroke subtype（脳卒中病型）
- Select Cerebral infarction（脳梗塞） / Intracerebral haemorrhage（脳内出血） / Subarachnoid haemorrhage（くも膜下出血） / Unknown subtype（病型不明）.
- Even if no diagnosis appears in the narrative, diagnoses in the directly related disease and related diseases fields may determine the subtype. Classify lacunar infarction, multiple cerebral infarctions, cardioembolic cerebral infarction, cerebellar infarction and medullary infarction as cerebral infarction; classify cerebral haemorrhage, putaminal haemorrhage, brainstem haemorrhage and cerebellar haemorrhage as intracerebral haemorrhage.
- When the fields and narrative name different subtypes, use the subtype in the fields. Use unknown subtype when the fields contain multiple subtypes without an identifiable main subtype, or only a term such as cerebrovascular disorder that does not specify a subtype.

### Incident type（事故類型）
- Determine this solely from the narrative (incident description, background factors, improvement measures and purpose of care). Do not use classification fields such as incident-content code（事例の内容コード） or procedure type（種類） as evidence.
- Choking or airway obstruction（窒息・気道閉塞）: classify as choking when choking, airway obstruction or food-bolus obstruction is explicitly stated, or food removal from the airway is described.
- Aspiration（誤嚥）: aspiration is explicitly stated and the choking criteria are not met. Do not infer aspiration solely from resuscitation, coughing or choking symptoms, hypoxia or pneumonia.
- Indeterminable（判定不能）: neither choking nor aspiration can be clearly established from the narrative.
- Treat the word aspiration in the course of this incident or a diagnosis after it, such as 'aspiration pneumonia' or 'aspiration was suspected', as explicit documentation of aspiration. Do not infer aspiration from 'pneumonia' alone without the word aspiration. General statements about 'risk of aspiration or choking' in improvement measures or background factors are not evidence.

### Material ingested（摂取物）
- Meals or food（食事・食品）: include rice porridge, jelly, liquid diets and oral nutritional supplements.
- Water or beverages（飲水・飲料）: include thickened beverages.
- Both（両方）: both meals or food and water or beverages were involved.
- Unknown（不明）: the material ingested cannot be determined from the narrative.

### Feeding assistance（摂食介助状況）
- Assisted（介助あり）: direct assistance, such as bringing food to the mouth, handling utensils or adjusting mouthful size, is explicitly documented (do not distinguish full from partial assistance). Serving, preparation, verbal prompting or observation alone do not count as assistance.
- Self-feeding（自力摂取）: the patient is explicitly described as eating or drinking independently.
- Unknown（不明）: whether assistance was provided cannot be determined from the narrative.
- If staff only served or set up the meal and left, and a later visit records that the patient 'had been able to eat' or 'was eating', treat this as explicit documentation of independent eating and classify as self-feeding.

### Presence of others（同席状況）
- Others present（他者同席あり）: staff, family or others were clearly nearby when the incident occurred or the abnormality appeared.
- Patient alone（患者のみ）: eating alone, others having left, or first discovery during a room visit is clearly documented. Do not infer that the patient was alone from self-feeding. If an abnormality was discovered through a nurse call, alarm or room visit after staff had left, classify as patient alone.
- Unknown（不明）: the presence of others cannot be determined from the narrative.

### Swallowing assessment（嚥下評価）
- Assessment explicitly completed（評価済みが明記）: the narrative explicitly states that a swallowing assessment had been completed.
- Explicitly before assessment or not performed（評価前・未実施が明記）: the narrative explicitly states that this was before a swallowing assessment or that it had not been performed.
- Indeterminable（判定不能）: swallowing assessment is not mentioned or cannot be established. Absence of documentation does not mean that it was not performed.

### Deviation from instructions（指示逸脱）
- Explicitly documented（明記あり）: the narrative explicitly documents deviation from instructions concerning food texture, fluids, observation, etc., or a failure of information transfer. Select this if any of the following is documented.
  - The food texture, amount or method differed from instructions, or instructions were not followed.
  - Necessary instructions (starting meals, fluid intake, food texture, etc.) had not been issued.
  - Necessary information (swallowing status, food texture, the course of coughing or choking symptoms, etc.) had not been communicated or shared with the assistant or responsible staff.
- None or unknown（なし・不明）: none of the above is explicitly documented in the narrative. If instructions had been issued and provision or assistance followed them, select none or unknown when only an unclear explanation or record of the rationale is described. Also select none or unknown for retrospective statements in background factors or improvement measures such as 'should have' or 'will consider', without documentation that instructions were absent, not followed or not communicated. When provision or assistance followed existing instructions, statements such as 'the instructions or diet type should have been changed', 'had not been changed' or 'judgement was insufficient' do not explicitly establish that instructions had not been issued; select none or unknown.

### Meal category（食事区分）
Determine the meal during which the incident occurred in the following order.
1. If the narrative or fields name the meal during which the incident occurred (breakfast, lunch, dinner, etc.), use that name. Do not use the name of another meal, such as dinner on the previous day. If a snack is specified, select Other or unknown（その他・不明）.
2. If no meal is named, use the incident time (or meal start time) stated in the narrative: Breakfast（朝食） 6:00–9:59, Lunch（昼食） 11:00–13:59, Dinner（夕食） 17:00–19:59. Other times are other or unknown.
3. If the narrative also lacks a time, use the incident time band field: 6:00–7:59 and 8:00–9:59 indicate breakfast, 12:00–13:59 lunch, and 18:00–19:59 dinner. The bands 10:00–11:59, 14:00–15:59 and 16:00–17:59 cross meal boundaries, so select other or unknown. All other time bands are also other or unknown.
- Options: Breakfast（朝食） / Lunch（昼食） / Dinner（夕食） / Other or unknown（その他・不明）.

### Life-saving intervention（救命介入） (classify only for Choking or airway obstruction（窒息・気道閉塞）; otherwise use an empty string)
- Yes（あり）: an intervention intended to save life or remove a foreign body (suction, back blows, abdominal thrusts, laryngoscopy, etc.) was performed.
- No（なし）: it can be established that no intervention intended to save life or remove a foreign body was performed.
- Unknown（不明）: use unknown if not documented.

### Involved-staff number of the direct assistant（直接介助者の当事者番号）
- The number in the involved staff field (e.g. 1 in '1: nurse ...'). This is the number of the involved staff member who directly assisted the patient's intake during the meal in which the incident occurred. For multiple staff, separate numbers with ASCII commas, e.g. 1,2. Use an empty string if identification is impossible.
- Direct assistance includes medication administration assistance immediately before the incident as well as feeding assistance. Do not include staff who only served, set up or observed and then left.
- If the person actually assisting when the incident occurred (or abnormality appeared) is listed in the involved staff field, select only that person (if several staff were responsible for assistance and one had already left, select only the person who remained).
- If the person assisting at the incident is not listed in the involved staff field (e.g. a nursing assistant or family member), or the abnormality appeared after the assistant left temporarily, use the involved-staff number of the person who directly assisted during that meal.
- Match people in the narrative ('first-year nurse', 'late-shift nurse', 'nurse A', etc.) to the involved staff field by occupation and years of experience (first year of experience means less than one completed year in the occupation).
- If only one person is listed in the involved staff field and their occupation matches the person described as providing direct assistance in the narrative, use that person's number.

## Output

Write one line of JSON per case (JSONL) to the specified output file. Format:

{"事例ID": "...", "items": {"脳卒中の位置づけ": {"value": "...", "source": "column name", "quote": "..."}, ... all 11 items ...}}

- value must be the exact option string above in Japanese (life-saving intervention and involved-staff number of the direct assistant may also be empty strings).
- quote must be a short, verbatim extract from the original text in the source column that supports the judgement, without changing punctuation, full-width or half-width characters, or spaces. Aim for approximately 20–80 characters. If several passages are needed, select the single most decisive passage.
- For values based on absence of documentation (Indeterminable（判定不能）, Unknown（不明）, None or unknown（なし・不明）, Other or unknown（その他・不明）, or an empty string), source and quote may be empty strings.
- When meal category is determined from the incident time band field, set source to 「発生時間帯」 and quote to that field's exact value.
