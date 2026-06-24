----- NOTES ONLY BELOW, NOTHING FOR CODE CONSIDERATIONS 

The following related Predicates are IGNORED, noted here for future reference

351 | Species:Sex         this is per OTU, not specimen
348 | Species:Region      to be inferred from Country]
352 | Species:Figures     
358 | Species:DeposB      200 records, but handled by checking 
359 | Species:DeposC      few records 
360 | Species:CurrStat    hierarchy

-----

Edits

Changed:
* two "HH" values to "H" for predicate ID 353
* "JT" to "NS" for "Encyrtus saliens" (paper hard to get, can't confirm)
* "F" to 'HT' (saw source)
* "H" to "HT" -  taxon name 468874
* "T" to "HT" - https://sfg.taxonworks.org/tasks/nomenclature/browse?taxon_name_id=503754 (unchecked)

These were the data that were problematic.  NS is "Not stated".  

taxonworks_development=# select *  from data_attributes where controlled_vocabulary_term_id = 353 and value in ( 'HH', 'JT', 'NS', 'F', 'HR', 'H');
   id    |       type        | attribute_subject_id | attribute_subject_type | controlled_vocabulary_term_id | import_predicate | value | created_by_id | updated_by_id | project_id |         created_at         |         updated_at
---------+-------------------+----------------------+------------------------+-------------------------------+------------------+-------+---------------+---------------+------------+----------------------------+----------------------------
 3136750 | InternalAttribute |               463516 | TaxonName              |                           353 |                  | HH    |            78 |            78 |         16 | 2019-10-01 05:43:14.515725 | 2019-10-01 05:43:14.515725
 3167649 | InternalAttribute |               468874 | TaxonName              |                           353 |                  | H     |            78 |            78 |         16 | 2019-10-01 06:05:03.229413 | 2019-10-01 06:05:03.229413
 3172053 | InternalAttribute |               469337 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:08:03.620751 | 2019-10-01 06:08:03.620751
 3176147 | InternalAttribute |               469939 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:11:00.298015 | 2019-10-01 06:11:00.298015
 3176892 | InternalAttribute |               470168 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:11:31.798679 | 2019-10-01 06:11:31.798679
 3177241 | InternalAttribute |               470301 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:11:45.890391 | 2019-10-01 06:11:45.890391
 3185446 | InternalAttribute |               471445 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:17:31.608774 | 2019-10-01 06:17:31.608774
 3187042 | InternalAttribute |               471658 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:18:35.460892 | 2019-10-01 06:18:35.460892
 3191360 | InternalAttribute |               472163 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:21:33.998185 | 2019-10-01 06:21:33.998185
 3195705 | InternalAttribute |               472651 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:24:28.06479  | 2019-10-01 06:24:28.06479
 3196609 | InternalAttribute |               472727 | TaxonName              |                           353 |                  | JT    |            78 |            78 |         16 | 2019-10-01 06:25:08.719982 | 2019-10-01 06:25:08.719982
 3204038 | InternalAttribute |               473405 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:30:12.609607 | 2019-10-01 06:30:12.609607
 3215965 | InternalAttribute |               474752 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:38:51.403092 | 2019-10-01 06:38:51.403092
 3244510 | InternalAttribute |               478291 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 06:58:30.223804 | 2019-10-01 06:58:30.223804
 3253406 | InternalAttribute |               479097 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 07:04:31.998324 | 2019-10-01 07:04:31.998324
 3283839 | InternalAttribute |               482359 | TaxonName              |                           353 |                  | HH    |            78 |            78 |         16 | 2019-10-01 07:24:25.386775 | 2019-10-01 07:24:25.386775
 3292304 | InternalAttribute |               483167 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 07:30:09.863912 | 2019-10-01 07:30:09.863912
 3300657 | InternalAttribute |               483928 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 07:36:01.647336 | 2019-10-01 07:36:01.647336
 3304911 | InternalAttribute |               484253 | TaxonName              |                           353 |                  | HR    |            78 |            78 |         16 | 2019-10-01 07:38:57.720704 | 2019-10-01 07:38:57.720704
 3325797 | InternalAttribute |               483181 | TaxonName              |                           353 |                  | F     |            78 |            78 |         16 | 2019-10-01 07:53:50.220252 | 2019-10-01 07:53:50.220252
 3335538 | InternalAttribute |               486621 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 08:00:33.858515 | 2019-10-01 08:00:33.858515
 3337842 | InternalAttribute |               510918 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 08:02:12.923934 | 2019-10-01 08:02:12.923934
 3345859 | InternalAttribute |               487418 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 08:07:32.974632 | 2019-10-01 08:07:32.974632
 3347951 | InternalAttribute |               487591 | TaxonName              |                           353 |                  | NS    |            78 |            78 |         16 | 2019-10-01 08:08:57.663264 | 2019-10-01 08:08:57.663264

 3266414 | InternalAttribute |               503754 | TaxonName              |                           353 |                  | T     |            78 |            78 |         16 | 2019-10-01 07:13:11.091232 | 2019-10-01 07:13:11.091232
