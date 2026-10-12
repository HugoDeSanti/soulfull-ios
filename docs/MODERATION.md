# Moderation: reports, blocks and removing content

Members can see each other's names and profile photos, finished practices, likes, and the comments they write under a practice, so the app has user-generated content. App Store Guideline 1.2 requires four things of it, and this is how each one is met:

| Guideline 1.2 asks for | Where it lives |
|---|---|
| A way to filter objectionable material | `community_display_name()` shows "A member" for a name containing an objectionable word or one that passes for the team (0028). A comment with a link or objectionable language is refused before it posts (`is_objectionable_comment()`, 0032). Photos have no automatic filter: reports catch them. |
| A way to report offensive content, with a timely response | "⋯" → **Report** on every other member, wherever they appear (feed, search, friends, requests, notifications), and "⋯" → **Report comment** on every comment. → `report-member` → `member_reports` + an email to info@. **We act within 24 hours.** |
| A way to block abusive users | "⋯" → **Block** (0028). You tab → **Blocked members** lists blocks and offers Unblock. |
| Published contact information | info@soulfullgatherings.com, in the app (You tab → Support, and the Report sheet) and on every legal page. |

The Terms (§VI, community standards) are what members agree to when they create an account. The agreement line is on the account sheet.

## When a report email arrives

**The promise is review within 24 hours, every day.** Whoever watches info@ owns this. The email gives the reason, the reporter's note, the member's full name, email, id and photo link, the practice line it came from or the comment (its text, the practice it was under and its id), and the report id. A comment report's subject starts "Comment report".

1. **Look.** Open the photo link, and read the name, the comment if there is one, and the note.
2. **Decide**, using Terms §VI: is it objectionable (harassment, hate, sexual content, violence, impersonation, spam, illegal)?
3. **Act.** Use the smallest action that removes the problem (SQL editor, as the project owner):

   ```sql
   -- See the report
   select * from public.member_reports where id = '<report id>';

   -- Delete a comment. It's gone for everyone; the report keeps its text
   -- (member_reports.comment_body).
   delete from public.practice_comments where id = '<comment id>';

   -- Remove a photo: the row first, then the file
   update public.profiles set avatar_url = null where id = '<member id>';
   -- then Storage → avatars → <member id>/ → delete the .jpg (SQL can't delete Storage objects)

   -- Clear a name. They show as "A member" until they set a new one.
   -- A linked guide is renamed from this too (0027).
   update public.profiles set full_name = null where id = '<member id>';

   -- Take them out of the feed while you decide
   update public.profiles set share_activity = false where id = '<member id>';
   ```

   - **Suspend:** Authentication → Users → the member → **Ban user** (pick a duration). A banned user can't sign in or refresh their session.
   - **Remove for good:** delete the user in the same screen. Everything of theirs cascades away except their practice plays, which are anonymised, because guides were paid from them.

4. **Close the report:**

   ```sql
   update public.member_reports
      set status = 'actioned',            -- or 'dismissed'
          resolution = 'Photo removed; warned by email',
          resolved_at = now()
    where id = '<report id>';
   ```

5. **Reply** to the reporter if they gave an email (it's in the report email). Keep it short. Never tell the reported member who reported them.

### Open reports

```sql
select created_at, reason, reported_name, content_title, comment_body, details, id
  from public.member_reports
 where status = 'open'
 order by created_at;
```

An open report older than 24 hours is a missed promise. Check this query whenever the inbox has been quiet for a day, in case an email went astray. The row is written before the email is sent, so the table is the record of truth.

## How the pieces behave

- **Block (0028).** The two members stop existing for each other: feed, search, friends, requests, likes, notifications, presence faces and follower faces. Counts still include everyone, because a count names nobody.
  - Blocking ends any friendship or request between them, and removes their likes on each other's practices and the notifications those likes made.
  - The blocked member is never told, and can't read the block.
  - Unblocking restores none of what the block removed.
- **Report.** A guest can report (safety isn't gated behind an account). Blocking needs an account, because a block has to outlive the session.
  - Limit: 20 reports per reporter per day, and **30 an hour from all guests together** (`report-member`, `member_reports.reporter_is_guest`, 0029): a guest id is free, so a per-reporter limit alone put no ceiling on what guests could send. Over it, a guest is told to try later; members are unaffected.
  - You can't report yourself.
- **Friend-request cooldown (0028).** When someone declines a request, the sender can't send that person another for **30 days**. They see: "You can send <name> another request 30 days after your last one was declined."
  - Withdrawing your own request starts no cooldown.
  - The person who declined can still send a request the other way.
- **Name filter.** The word list is in `is_objectionable_name()` (0028). It matches whole words, so names like "Scunthorpe" pass. To add a word, use `create or replace function` with the longer list in a new migration. Never edit 0028 after it has been applied.
- **Likes.** A like that is unliked and liked again within 24 hours still shows in the bell, but doesn't buzz the phone a second time (`notifications.silent`).
- **Comments (0032).** Members comment under a movement sequence, a recipe or a session; never a journal prompt.
  - Only members read and write them (practice pages are behind the account gate, and the server refuses a guest). A member deletes their own; nobody edits one.
  - Refused before posting: a link (`http://`, `https://`, `www.`), a word from `is_objectionable_comment()` (slurs and hard profanity, whole words, English and Spanish; shorter than the name list on purpose, so a member can name what they've lived through), and a 21st comment in an hour. To change the word list, `create or replace function` in a new migration.
  - A block hides each member's comments from the other, both ways, through `community_members`. Nothing is deleted, and unblocking brings them back.
  - Deleting an account deletes its comments.

## Verifying it live (once, after applying 0028 and deploying `report-member`)

Use two confirmed test members, or run the checks in the header of 0028 inside `begin … rollback`. In the app:

1. A reports B from a feed line. The row is in `member_reports` and the email arrives at info@.
2. A blocks B. B's lines leave A's feed, and A's leave B's. A's name search for B is empty, and B's for A is too.
3. A unblocks B from the You tab. Both are visible to each other again.
4. A declines B's request. B's new request to A gets the cooldown message, and A can still send B one.

After applying 0032 and deploying `report-member` v3:

5. A comments on a movement sequence. B sees it; a comment with a link is refused with the links message.
6. B reports A's comment. The row has `comment_id` and `comment_body`, and the email quotes it.
7. B blocks A. Each stops seeing the other's comments; a third member still sees both.
