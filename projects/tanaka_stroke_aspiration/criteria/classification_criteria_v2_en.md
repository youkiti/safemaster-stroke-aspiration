This is an English translation for readers. The Japanese original (classification_criteria_v2_ja.md) records the classification criteria used.

# Stage 2 classification criteria v2 (25 October 2026)

## Information permitted for classification

In addition to the narrative (incident description（事例の内容）, background factors（背景要因） and improvement measures（改善策）), the fields above the case narrative (directly related disease（直接関連する疾患名）, related diseases（関連する疾患名）, incident time band（発生時間帯）, purpose of care（医療行為の目的）, patient state immediately before the incident（直前の患者の状態）, involved staff（当事者）, etc.) may be used as evidence. Minimise unknown values where possible and classify items that can reasonably be determined from the recorded information.

## Criteria for each item

### Role of stroke（脳卒中の位置づけ） (changed in v2)
- Main condition or sequelae under management（主病態・管理中の後遺症）: the main condition for the admission, or stroke sequelae being managed during the admission. Select this when the directly related disease is stroke (including cerebral infarction, cerebral haemorrhage or sequelae).
- Comorbidity or history（併存・既往）: admission for another disease, with stroke recorded as a comorbidity or past history. Select this when the directly related disease is a disease other than stroke and stroke appears only in related diseases or the history in the narrative.
- If the directly related disease names the incident itself, such as aspiration or choking, use the related diseases and narrative to decide whether the main condition managed during admission was stroke (including sequelae).
- Indeterminable（判定不能）: the fields and narrative together do not establish whether stroke was the main condition or a comorbidity or history.

### Stroke subtype（脳卒中病型） (changed in v2)
- Select Cerebral infarction（脳梗塞） / Intracerebral haemorrhage（脳内出血） / Subarachnoid haemorrhage（くも膜下出血） / Unknown subtype（病型不明）.
- Even if no diagnosis appears in the narrative, diagnoses in the directly related disease and related diseases fields may determine the subtype. Classify lacunar infarction, multiple cerebral infarctions, cardioembolic cerebral infarction, cerebellar infarction and medullary infarction as cerebral infarction; classify cerebral haemorrhage, putaminal haemorrhage, brainstem haemorrhage and cerebellar haemorrhage as intracerebral haemorrhage.
- When the fields and narrative name different subtypes, use the subtype in the fields. Use unknown subtype when the fields contain multiple subtypes without an identifiable main subtype, or only a term such as cerebrovascular disorder that does not specify a subtype.

### Incident type（事故類型） (unchanged from v1)
- Choking or airway obstruction（窒息・気道閉塞）: classify as choking when choking, airway obstruction or food-bolus obstruction is explicitly stated, or food removal from the airway is described.
- Aspiration（誤嚥）: aspiration is explicitly stated and the choking criteria are not met. Do not infer aspiration solely from resuscitation, coughing or choking symptoms, hypoxia or pneumonia.
- Indeterminable（判定不能）: neither choking nor aspiration can be clearly established from the narrative.

### Material ingested（摂取物） (unchanged from v1)
- Meals or food（食事・食品）: include rice porridge, jelly, liquid diets and oral nutritional supplements.
- Water or beverages（飲水・飲料）: include thickened beverages.
- Both（両方）: both meals or food and water or beverages were involved.
- Unknown（不明）: the material ingested cannot be determined from the narrative.

### Feeding assistance（摂食介助状況） (unchanged from v1)
- Assisted（介助あり）: direct assistance, such as bringing food to the mouth, handling utensils or adjusting mouthful size, is explicitly documented (do not distinguish full from partial assistance). Serving, preparation, verbal prompting or observation alone do not count as assistance.
- Self-feeding（自力摂取）: the patient is explicitly described as eating or drinking independently.
- Unknown（不明）: whether assistance was provided cannot be determined from the narrative.

### Presence of others（同席状況） (unchanged from v1)
- Others present（他者同席あり）: staff, family or others were clearly nearby when the incident occurred or the abnormality appeared.
- Patient alone（患者のみ）: eating alone, others having left, or first discovery during a room visit is clearly documented. Do not infer that the patient was alone from self-feeding.
- Unknown（不明）: the presence of others cannot be determined from the narrative.

### Swallowing assessment（嚥下評価） (unchanged from v1)
- Assessment explicitly completed（評価済みが明記）: the narrative explicitly states that a swallowing assessment had been completed.
- Explicitly before assessment or not performed（評価前・未実施が明記）: the narrative explicitly states that this was before a swallowing assessment or that it had not been performed.
- Indeterminable（判定不能）: swallowing assessment is not mentioned or cannot be established. Absence of documentation does not mean that it was not performed.

### Deviation from instructions（指示逸脱） (unchanged from v1)
- Explicitly documented（明記あり）: the narrative explicitly documents deviation from instructions concerning food texture, fluids, observation, etc., or a failure of information transfer.
- None or unknown（なし・不明）: the above is not explicitly documented in the narrative.

### Meal category（食事区分） (changed in v2)
Determine the meal during which the incident occurred in the following order.

1. If the narrative or fields name the meal during which the incident occurred (breakfast, lunch, dinner, etc.), use that name. Do not use the name of another meal, such as dinner on the previous day. If a snack is specified, select Other or unknown（その他・不明）.
2. If no meal is named, use the incident time (or meal start time) stated in the narrative: Breakfast（朝食） 6:00–9:59, Lunch（昼食） 11:00–13:59, Dinner（夕食） 17:00–19:59. Other times are other or unknown.
3. If the narrative also lacks a time, use the incident time band field: 6:00–7:59 and 8:00–9:59 indicate breakfast, 12:00–13:59 lunch, and 18:00–19:59 dinner. The bands 10:00–11:59, 14:00–15:59 and 16:00–17:59 cross meal boundaries, so select other or unknown. All other time bands are also other or unknown.

Addendum (rule added during human review; not part of the AI prompt): intake that was not part of a regular meal (swallowing training and food brought by visitors) is classified as Other or unknown（その他・不明）, even if the time overlaps a meal period.

### Life-saving intervention（救命介入） (unchanged from v1; classify only for Choking or airway obstruction（窒息・気道閉塞）)
- Yes（あり）: an intervention intended to save life or remove a foreign body (suction, back blows, abdominal thrusts, laryngoscopy, etc.) was performed.
- No（なし）: it can be established that no intervention intended to save life or remove a foreign body was performed.
- Unknown（不明）: use unknown if not documented.

### Involved-staff number of the direct assistant（直接介助者の当事者番号） (unchanged from v1)
- The number in the involved staff field above the case narrative. For multiple staff, separate numbers with ASCII commas, e.g. 1,2. Leave blank if identification is impossible.

## Additional rules for AI draft classification

- Incident type（事故類型）: use only the narrative; do not use classification fields such as incident-content code（事例の内容コード） as evidence. Treat the word aspiration in the course of this incident or a diagnosis after it, such as 'aspiration pneumonia' or 'aspiration was suspected', as explicit documentation of aspiration. General statements about 'risk of aspiration or choking' in improvement measures are not evidence.
- Feeding assistance（摂食介助状況） and presence of others（同席状況）: if staff only served or set up the meal and left, and a room visit records that the patient 'had been able to eat', classify as Self-feeding（自力摂取）. If an abnormality was discovered through a nurse call, alarm or room visit after staff had left, classify as Patient alone（患者のみ）.
- Deviation from instructions（指示逸脱）: select Explicitly documented（明記あり） if intake differed from instructions, necessary instructions had not been issued, or necessary information had not been communicated to the assistant. If provision or assistance followed existing instructions, retrospective statements such as 'should have been changed', 'had not been changed' or 'judgement was insufficient' do not qualify as explicitly documented deviation.
- Involved-staff number of the direct assistant（直接介助者の当事者番号）: include medication administration assistance. Exclude people who only served, set up or observed. Match people in the narrative to the involved staff field by occupation and years of experience (first year of experience means less than one completed year). If only one person is listed and the occupation matches, use that number. If the person assisting at the incident is listed, select only that person. If that person is not listed, or the abnormality appeared after the assistant left temporarily, select the involved staff member who directly assisted during that meal.
