/**
 * The Relationship Core sequence: the one order in which every member meets
 * the Core questions. Q1-Q15 are onboarding; after that a member gets the
 * next five they have not answered, once per logical day (see schedule.ts).
 *
 * The order is deliberately NOT the array order of catalog.ts. It is written
 * out here so that adding, moving or regrouping questions in the catalog can
 * never shift what Q7 is.
 *
 * FROZEN. test/fixtures/coreSequence.lock.json records every position, and
 * test/relationshipCoreFreeze.test.cjs fails when one changes:
 *   - new questions are APPENDED to the end — never inserted, never moved;
 *   - a question whose meaning or options change gets a new id (next
 *     version) appended here; the old id stays where it is, retired with
 *     `active: false` in the catalog, so nobody is asked it again and
 *     answers already given keep their place;
 *   - nothing is ever removed.
 *
 * Q1-Q15 are all comparable and mix areas (relationship 4, values 4,
 * communication 3, lifestyle 3, humor 1), so two members who only finished
 * onboarding already share fifteen answers across more than one kind of
 * reason. The six importance questions (which set a member's own weights and
 * are never compared) close days 2-7, at Q20, 25, 30, 35, 40 and 45.
 */
export const CORE_SEQUENCE: readonly string[] = [
  // --- Q1-Q15: onboarding ------------------------------------------------------
  "relationship_free_evening_v1",
  "relationship_daily_contact_v1",
  "relationship_pace_v1",
  "relationship_togetherness_balance_v1",
  "relationship_humor_style_v1",
  "relationship_conflict_timing_v1",
  "relationship_marriage_view_v1",
  "relationship_plans_or_spontaneous_v1",
  "relationship_jealousy_view_v1",
  "relationship_feelings_expression_v1",
  "relationship_children_view_v1",
  "relationship_phone_privacy_v1",
  "relationship_active_lifestyle_v1",
  "relationship_affection_style_v1",
  "relationship_money_sharing_v1",
  // --- Q16 onwards: five a day -----------------------------------------------
  "relationship_exclusivity_timing_v1",
  "relationship_late_reply_v1",
  "relationship_alone_time_v1",
  "relationship_weekend_style_v1",
  "relationship_goal_importance_v1",

  "relationship_future_talk_v1",
  "relationship_raising_issues_v1",
  "relationship_honesty_style_v1",
  "relationship_nights_out_v1",
  "relationship_values_importance_v1",

  "relationship_moving_in_v1",
  "relationship_friends_one_on_one_v1",
  "relationship_daily_rhythm_v1",
  "relationship_tidiness_v1",
  "relationship_lifestyle_importance_v1",

  "relationship_teasing_v1",
  "relationship_laugh_together_v1",
  "relationship_apart_contact_v1",
  "relationship_decision_making_v1",
  "relationship_humor_importance_v1",

  "relationship_together_activity_v1",
  "relationship_new_activities_v1",
  "relationship_long_distance_v1",
  "relationship_money_approach_v1",
  "relationship_interests_importance_v1",

  "relationship_music_together_v1",
  "relationship_music_discovery_v1",
  "relationship_public_affection_v1",
  "relationship_friends_circle_v1",
  "relationship_music_importance_v1",

  "relationship_household_split_v1",
  "relationship_work_life_balance_v1",
  "relationship_joke_when_tense_v1",
  "relationship_exes_friendship_v1",
  "relationship_holiday_style_v1",

  "relationship_surprises_v1",
  "relationship_social_media_sharing_v1",
  "relationship_pets_at_home_v1",
  "relationship_hobbies_shared_v1",
  "relationship_family_involvement_v1",

  "relationship_phones_together_v1",
  "relationship_career_centrality_v1",
  "relationship_travel_frequency_v1",
  "relationship_special_days_v1",
  "relationship_city_or_nature_v1",

  "relationship_hosting_v1",
  "relationship_traditions_v1",
  "relationship_learning_together_v1",
  "relationship_family_visits_v1",
];

const POSITION = new Map(CORE_SEQUENCE.map((id, index) => [id, index + 1]));

/** 1-based place of a question in the Core sequence, or null when it is not a Core question. */
export function corePosition(questionId: string): number | null {
  return POSITION.get(questionId) ?? null;
}
