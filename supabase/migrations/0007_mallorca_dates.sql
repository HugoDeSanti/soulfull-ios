-- 0007_mallorca_dates.sql
-- Bring Mallorca back into the catalog.
--
-- `SupabaseService.fetchRetreats()` filters `end_date >= today`, and Mallorca's
-- seeded dates were in the past — so the ONE retreat with curated
-- `RetreatExperience` brochure content (and the only `PostBooking` trip) was
-- invisible, leaving every retreat in the app on the concise fallback layout.
--
-- The dates below are July 21–26 deliberately: `RetreatExperience.mallorca`
-- hardcodes `dateRange: "July 21–26"` as brochure copy and that string WINS on
-- the detail screen. If these dates ever change, change that literal in
-- Models.swift to match or the screen contradicts itself.

update public.retreats
   set start_date = date '2027-07-21',
       end_date   = date '2027-07-26'
 where name = 'Mallorca';
