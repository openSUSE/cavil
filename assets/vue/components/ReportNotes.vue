<template>
  <div class="report-notes">
    <div v-if="showRelevanceFilter" class="report-notes-toolbar" data-notes-toolbar>
      <label class="report-notes-relevance-toggle">
        <input type="checkbox" v-model="relevantOnly" class="form-check-input" data-notes-relevant-only />
        Only relevant notes
      </label>
      <span class="report-notes-relevance-hint">{{ relevant }} of {{ total }} relevant to this report</span>
    </div>
    <div v-if="initialLoading" class="report-notes-loading">
      <i class="fa-solid fa-spinner fa-pulse"></i> Loading notes...
    </div>
    <div v-else>
      <div v-if="notes.length === 0 && !loadError" class="report-notes-empty">
        <i class="fa-regular fa-note-sticky"></i>
        <p class="mb-0">{{ emptyMessage }}</p>
      </div>
      <ul v-else class="report-notes-list">
        <li
          v-for="c in notes"
          :key="c.id"
          :id="`note-${c.id}`"
          :class="[
            'report-note',
            {
              'report-note-lawyer-only': c.lawyer_only,
              'report-note-deemphasized': isNonRelevant(c)
            }
          ]"
          :data-note-id="c.id"
        >
          <span v-if="isNonRelevant(c)" class="report-note-relevance-overlay" data-note-relevance-overlay>
            <span class="report-note-relevance-label">Not relevant to this report</span>
          </span>
          <div class="report-note-header">
            <span class="report-note-avatar" :title="authorTitle(c)">
              {{ initial(c) }}
            </span>
            <div class="report-note-byline">
              <span class="report-note-author" :title="authorTitle(c)">{{ c.author.login }}</span>
              <span
                v-if="c.author.badge"
                :class="['report-note-role', `report-note-role-${c.author.badge}`]"
                :title="`Role: ${c.author.badge}`"
                :data-note-role="c.author.badge"
                >{{ c.author.badge }}</span
              >
              wrote
              <a
                class="report-note-permalink"
                :href="permalink(c)"
                :title="formatExact(c.created_epoch)"
                data-note-permalink
                >{{ formatRelative(c.created_epoch) }}</a
              >
              <span
                v-if="c.edited_epoch"
                class="report-note-edited"
                :title="`Edited ${formatExact(c.edited_epoch)}`"
                data-note-edited
                >· edited {{ formatRelative(c.edited_epoch) }}</span
              >
              <span v-if="showPackageName && c.package_name">
                for
                <template v-if="c.original_package && c.original_package.id !== null">
                  <a
                    :href="reportUrl(c.original_package.id)"
                    target="_blank"
                    rel="noopener"
                    class="report-note-package-link"
                    :title="originTitle(c)"
                    >{{ c.package_name }}</a
                  >
                </template>
                <span v-else class="report-note-package-name">{{ c.package_name }}</span>
              </span>
            </div>
            <div class="report-note-badges">
              <a
                v-if="isFromOtherReport(c)"
                class="report-note-badge origin-report-badge"
                :href="reportUrl(c.original_package.id)"
                target="_blank"
                rel="noopener"
                :title="originBadgeTitle(c)"
                data-note-origin-badge
              >
                <i class="fa-solid fa-code-branch" aria-hidden="true"></i> from report #{{ c.original_package.id
                }}<span v-if="isObsoleteOrigin(c)" class="report-note-origin-state" data-note-origin-obsolete>
                  · obsolete</span
                >
              </a>
              <span
                v-if="c.ai_assisted"
                class="report-note-badge ai-assisted-badge"
                title="Created with AI assistance"
                data-note-ai-assisted
              >
                <i class="fa-solid fa-robot"></i> AI assisted
              </span>
              <span
                v-if="c.lawyer_only"
                class="report-note-badge lawyer-only-badge"
                title="Visible to lawyers and admins only"
              >
                <i class="fa-solid fa-scale-balanced"></i> Lawyers only
              </span>
              <span
                v-for="t in c.tags || []"
                :key="t"
                class="report-note-tag"
                :title="`Tag: ${t}`"
                :data-note-tag="t"
                >{{ t }}</span
              >
              <button
                v-if="allowActions && c.can_edit && editingId !== c.id"
                type="button"
                class="report-note-edit cavil-icon-action"
                :disabled="savingId === c.id"
                title="Edit this note"
                :data-note-edit="c.id"
                @click="startEdit(c)"
              >
                <i class="fa-solid fa-pen"></i>
              </button>
              <button
                v-if="allowActions && c.can_delete && editingId !== c.id"
                type="button"
                class="report-note-delete cavil-icon-action cavil-icon-action-danger"
                :disabled="deletingId === c.id"
                title="Delete this note"
                :data-note-delete="c.id"
                @click="deleteNote(c)"
              >
                <i class="fa-solid fa-trash"></i>
              </button>
            </div>
          </div>
          <div v-if="editingId === c.id" class="report-note-edit-pane" data-note-edit-pane>
            <TagInput ref="editTagInput" v-model="editTags" :suggestions="knownTags" :data-key="`edit-${c.id}`" />
            <MarkdownComposer
              v-model="editDraft"
              :saving="savingId === c.id"
              :error="editError"
              save-label="Save"
              save-busy-label="Saving…"
              show-cancel
              :data-attr="`edit-${c.id}`"
              @save="saveEdit(c)"
              @cancel="cancelEdit"
            />
          </div>
          <div v-else class="report-note-body markdown-body" v-html="c.body_html"></div>
        </li>
      </ul>

      <div v-if="loadError" class="report-notes-error">
        <i class="fa-solid fa-triangle-exclamation"></i> {{ loadError }}
        <button type="button" class="report-note-retry" @click="loadMore">Retry</button>
      </div>

      <div v-if="!loadError && hasMore" ref="sentinel" class="report-notes-sentinel" data-notes-sentinel>
        <i v-if="loadingMore" class="fa-solid fa-spinner fa-pulse"></i>
        <span v-else>Scroll to load more</span>
      </div>

      <div v-if="showComposer" class="report-note-form" data-note-form>
        <label class="report-note-form-label">Add a note</label>
        <TagInput ref="newTagInput" v-model="tags" :suggestions="knownTags" data-key="new" />
        <MarkdownComposer
          v-model="draft"
          :saving="submitting"
          :error="submitError"
          :placeholder="formPlaceholder"
          save-label="Note"
          save-busy-label="Posting…"
          data-attr="new"
          @save="submit"
        >
          <template #leading>
            <label v-if="canPostLawyerOnly" class="report-note-lawyer-toggle">
              <input type="checkbox" v-model="lawyerOnly" class="form-check-input" data-note-lawyer-only />
              Lawyers only
            </label>
          </template>
        </MarkdownComposer>
      </div>
    </div>
  </div>
</template>

<script>
import MarkdownComposer from './MarkdownComposer.vue';
import TagInput from './TagInput.vue';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'ReportNotes',
  components: {MarkdownComposer, TagInput},
  props: {
    pkgId: {type: Number, default: null},
    endpoint: {type: String, default: null},
    canPostLawyerOnly: {type: Boolean, default: false},
    seekNoteId: {type: Number, default: null},
    showComposer: {type: Boolean, default: true},
    allowActions: {type: Boolean, default: true},
    emptyMessage: {type: String, default: 'No notes yet. Leave the first one to help future reviewers.'},
    showPackageName: {type: Boolean, default: false},
    permalinkToOrigin: {type: Boolean, default: false},
    filterTags: {type: Array, default: () => []}
  },
  emits: ['counts-changed'],
  computed: {
    formPlaceholder() {
      return this.canPostLawyerOnly
        ? 'Use Markdown for formatting. Lawyer-only notes stay visible to lawyers and admins.'
        : 'Use Markdown for formatting.';
    },
    listEndpoint() {
      return this.endpoint || `/reviews/notes/${this.pkgId}`;
    },
    // Show the "Only relevant notes" toggle only when filtering would actually
    // help: there must be both relevant notes to keep and non-relevant ones to
    // hide. (De-emphasis itself is unconditional - any non-relevant note recedes
    // whether or not relevant siblings exist.)
    showRelevanceFilter() {
      return (
        this.pkgId !== null &&
        !this.showPackageName &&
        this.total !== null &&
        this.relevant !== null &&
        this.relevant > 0 &&
        this.relevant < this.total
      );
    }
  },
  data() {
    return {
      notes: [],
      hasMore: false,
      initialLoading: true,
      loadingMore: false,
      loadError: null,
      submitting: false,
      submitError: null,
      deletingId: null,
      draft: '',
      lawyerOnly: false,
      tags: [],
      knownTags: [],
      relevantOnly: false,
      total: null,
      relevant: null,
      editingId: null,
      editDraft: '',
      editError: null,
      editTags: [],
      savingId: null,
      observer: null,
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  async mounted() {
    await this.loadMore();
    if (this.seekNoteId !== null) await this.seekToNote(this.seekNoteId);
    this.setupObserver();
    // Tag autocomplete is only useful where the reviewer can author/edit notes.
    if (this.showComposer || this.allowActions) this.loadKnownTags();
  },
  beforeUnmount() {
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }
  },
  watch: {
    // Changing a filter restarts the keyset scroll from the top, the same reset
    // semantics the other filtered infinite-scroll pages use.
    filterTags() {
      this.reloadFromTop();
    },
    relevantOnly() {
      this.reloadFromTop();
    }
  },
  methods: {
    formatRelative(epoch) {
      return moment(epoch * 1000).fromNow();
    },
    formatExact(epoch) {
      return moment(epoch * 1000).format('YYYY-MM-DD HH:mm');
    },
    initial(c) {
      return (c.author.login || '?').charAt(0).toUpperCase();
    },
    authorTitle(c) {
      return c.author.fullname ? `${c.author.login} (${c.author.fullname})` : c.author.login;
    },
    reportUrl(id) {
      return `/reviews/details/${id}`;
    },
    permalink(c) {
      if (this.permalinkToOrigin && c.original_package && c.original_package.id !== null) {
        return `${this.reportUrl(c.original_package.id)}#note-${c.id}`;
      }

      // Anchor on this review (notes are shared across versions, so the
      // anchor resolves no matter which version the user shares).
      return `/reviews/details/${this.pkgId}#note-${c.id}`;
    },
    originTitle(c) {
      const link = c.original_package.external_link ? ` (${c.original_package.external_link})` : '';
      return `Opens originating report${link} in a new tab`;
    },
    isFromOtherReport(c) {
      return (
        this.pkgId !== null &&
        c.original_package &&
        c.original_package.id !== null &&
        c.original_package.id !== this.pkgId
      );
    },
    isCurrentReview(c) {
      return this.pkgId !== null && c.original_package && c.original_package.id === this.pkgId;
    },
    // Relevant = written on this report, or inherited from a report with an
    // identical license report (so the note applies verbatim).
    isRelevant(c) {
      return this.isCurrentReview(c) || c.same_report === true;
    },
    // Inherited from a report with different licensing - de-emphasized in a
    // mixed list so the relevant notes stand out by contrast.
    isNonRelevant(c) {
      return this.isFromOtherReport(c) && !this.isRelevant(c);
    },
    isObsoleteOrigin(c) {
      return !!(c.original_package && c.original_package.state === 'obsolete');
    },
    originBadgeTitle(c) {
      if (c.same_report === true) {
        return `Identical license report — this note applies to your report. ${this.originTitle(c)}`;
      }
      const state = c.original_package && c.original_package.state;
      const stateText = state ? ` (report state: ${state})` : '';
      return `From a report with different licensing${stateText}. ${this.originTitle(c)}`;
    },
    reloadFromTop() {
      if (this.observer) {
        this.observer.disconnect();
        this.observer = null;
      }
      this.notes = [];
      this.hasMore = false;
      this.initialLoading = true;
      this.loadMore().then(() => this.setupObserver());
    },
    setupObserver() {
      const target = this.$refs.sentinel;
      if (!target || typeof IntersectionObserver === 'undefined') return;
      this.observer = new IntersectionObserver(entries => {
        for (const entry of entries) {
          if (entry.isIntersecting && this.hasMore && !this.loadingMore) this.loadMore();
        }
      });
      this.observer.observe(target);
    },
    async loadMore() {
      if (this.loadingMore) return;
      this.loadError = null;
      if (this.notes.length === 0) this.initialLoading = true;
      else this.loadingMore = true;
      try {
        const qs = {limit: 20};
        if (this.notes.length > 0) qs.before_id = this.notes[this.notes.length - 1].id;
        if (this.filterTags.length) qs.tags_json = JSON.stringify(this.filterTags);
        if (this.relevantOnly) qs.relevant_only = 1;
        const res = await this.ua.get(this.listEndpoint, {query: qs});
        if (!res.isSuccess) {
          this.loadError = `Failed to load notes (HTTP ${res.statusCode})`;
          return;
        }
        const data = await res.json();
        this.notes.push(...data.notes);
        this.hasMore = !!data.has_more;
        if (data.total !== undefined) this.total = data.total;
        if (data.relevant !== undefined) this.relevant = data.relevant;
        this.$emit('counts-changed', {total: data.total, lawyer_only: data.lawyer_only});
        await this.$nextTick();
        this.setupObserver();
      } catch (err) {
        this.loadError = err.message || 'Failed to load notes';
      } finally {
        this.initialLoading = false;
        this.loadingMore = false;
      }
    },
    async submit() {
      if (!this.showComposer || this.pkgId === null) return;
      this.$refs.newTagInput?.commitDraft();
      const body = this.draft.trim();
      if (!body || this.submitting) return;
      this.submitting = true;
      this.submitError = null;
      try {
        const form = {body, lawyer_only: this.lawyerOnly ? '1' : '0'};
        if (this.tags.length) form.tags_json = JSON.stringify(this.tags);
        const res = await this.ua.post(`/reviews/notes/${this.pkgId}`, {form});
        if (!res.isSuccess) {
          let msg = `Failed (HTTP ${res.statusCode})`;
          try {
            const data = await res.json();
            if (data && data.error) msg = data.error;
          } catch (_) {
            // ignore
          }
          this.submitError = msg;
          return;
        }
        const data = await res.json();
        this.notes.unshift(data.note);
        this.draft = '';
        this.lawyerOnly = false;
        this.tags = [];
        // Re-fetch counts via a HEAD-like call would be cheap; piggyback on
        // the next page request instead: refresh counts by re-counting locally
        // + bumping totals from the server's lawyer flag.
        this.$emit('counts-changed', {bump: 1, lawyer_only_bump: data.note.lawyer_only ? 1 : 0});
      } catch (err) {
        this.submitError = err.message || 'Failed to submit note';
      } finally {
        this.submitting = false;
      }
    },
    async seekToNote(targetId) {
      // Paginate until the note shows up or the list is exhausted. Bounded
      // by a safety limit so a non-existent (or someone-else's-package) id
      // can't trigger an infinite loop.
      let safety = 50;
      while (!this.notes.find(c => c.id === targetId) && this.hasMore && safety-- > 0) {
        await this.loadMore();
        if (this.loadError) return;
      }
      await this.$nextTick();
      const el = document.getElementById(`note-${targetId}`);
      if (!el) return;
      el.scrollIntoView({behavior: 'smooth', block: 'center'});
      el.classList.add('report-note-highlight');
      setTimeout(() => el.classList.remove('report-note-highlight'), 2000);
    },
    startEdit(c) {
      this.editingId = c.id;
      this.editDraft = c.body;
      this.editError = null;
      this.editTags = Array.isArray(c.tags) ? c.tags.slice() : [];
    },
    cancelEdit() {
      this.editingId = null;
      this.editDraft = '';
      this.editError = null;
      this.editTags = [];
    },
    async saveEdit(c) {
      // The edit pane lives inside v-for, so Vue collects its ref into an array.
      const editTagInput = this.$refs.editTagInput;
      (Array.isArray(editTagInput) ? editTagInput[0] : editTagInput)?.commitDraft();
      const body = (this.editDraft || '').trim();
      if (!body || this.savingId === c.id) return;
      this.savingId = c.id;
      this.editError = null;
      try {
        const form = {body, tags_json: JSON.stringify(this.editTags)};
        const res = await this.ua.patch(`/reviews/notes/${c.id}`, {form});
        if (!res.isSuccess) {
          let msg = `Failed (HTTP ${res.statusCode})`;
          try {
            const data = await res.json();
            if (data && data.error) msg = data.error;
          } catch (_) {
            // ignore
          }
          this.editError = msg;
          return;
        }
        const data = await res.json();
        const idx = this.notes.findIndex(x => x.id === c.id);
        if (idx >= 0) this.notes.splice(idx, 1, data.note);
        this.cancelEdit();
      } catch (err) {
        this.editError = err.message || 'Failed to save edit';
      } finally {
        this.savingId = null;
      }
    },
    async loadKnownTags() {
      try {
        const res = await this.ua.get('/reviews/notes/tags.json');
        if (!res.isSuccess) return;
        const data = await res.json();
        if (Array.isArray(data.tags)) this.knownTags = data.tags;
      } catch (_) {
        // Autocomplete is a convenience; a failed fetch just means no suggestions.
      }
    },
    async deleteNote(c) {
      // eslint-disable-next-line no-alert
      if (!window.confirm('Delete this note?')) return;
      this.deletingId = c.id;
      try {
        const res = await this.ua.delete(`/reviews/notes/${c.id}`);
        if (!res.isSuccess) return;
        const idx = this.notes.findIndex(x => x.id === c.id);
        if (idx >= 0) this.notes.splice(idx, 1);
        this.$emit('counts-changed', {bump: -1, lawyer_only_bump: c.lawyer_only ? -1 : 0});
      } finally {
        this.deletingId = null;
      }
    }
  }
};
</script>

<style>
.report-notes {
  padding-bottom: 24px;
}
.report-notes-loading,
.report-notes-empty {
  align-items: center;
  border: 1px dashed #d0d7de;
  border-radius: 8px;
  color: #57606a;
  display: flex;
  flex-direction: column;
  gap: 12px;
  justify-content: center;
  margin: 24px 0;
  padding: 40px 20px;
  text-align: center;
}
.report-notes-empty i {
  color: #afb8c1;
  font-size: 28px;
}
.report-notes-error {
  align-items: center;
  background: #ffebe9;
  border: 1px solid #ff818266;
  border-radius: 6px;
  color: #82071e;
  display: flex;
  gap: 8px;
  margin: 12px 0;
  padding: 8px 12px;
}
.report-note-retry {
  background: transparent;
  border: 1px solid #cf222e;
  border-radius: 6px;
  color: #cf222e;
  cursor: pointer;
  margin-left: auto;
  padding: 2px 10px;
}
.report-notes-list {
  list-style: none;
  margin: 0;
  padding: 0;
}
.report-note {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 8px;
  margin-bottom: 16px;
  overflow: hidden;
  position: relative;
}
/* Notes inherited from a report with different licensing recede so the relevant
   ones stand out, while the reason remains fully readable above the fade. */
.report-note-deemphasized .report-note-header,
.report-note-deemphasized .report-note-body {
  opacity: 0.55;
  transition: opacity 0.15s ease;
}
.report-note-relevance-overlay {
  align-items: center;
  background: repeating-linear-gradient(
    -45deg,
    rgba(246, 248, 250, 0.5) 0,
    rgba(246, 248, 250, 0.5) 14px,
    rgba(208, 215, 222, 0.18) 14px,
    rgba(208, 215, 222, 0.18) 28px
  );
  color: #6e7781;
  display: flex;
  font-size: 11px;
  font-weight: 600;
  inset: 0;
  justify-content: center;
  letter-spacing: 0;
  opacity: 1;
  padding: 16px;
  pointer-events: none;
  position: absolute;
  text-align: center;
  transition:
    opacity 0.15s ease,
    visibility 0.15s ease;
  visibility: visible;
  z-index: 1;
}
.report-note-relevance-label {
  background: rgba(255, 255, 255, 0.82);
  border: 1px solid rgba(110, 119, 129, 0.22);
  border-radius: 2em;
  box-shadow: 0 1px 2px rgba(31, 35, 40, 0.04);
  padding: 2px 10px;
}
.report-note-deemphasized:hover .report-note-relevance-overlay,
.report-note-deemphasized:focus-within .report-note-relevance-overlay {
  opacity: 0;
  visibility: hidden;
}
.report-note-deemphasized:hover .report-note-header,
.report-note-deemphasized:hover .report-note-body,
.report-note-deemphasized:focus-within .report-note-header,
.report-note-deemphasized:focus-within .report-note-body {
  opacity: 1;
}
.report-note-lawyer-only {
  border-left: 4px solid #bf8700;
  background: linear-gradient(180deg, rgba(255, 244, 207, 0.45) 0%, #ffffff 60px);
}
.report-note-header {
  align-items: center;
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  padding: 10px 14px;
}
.report-note-lawyer-only .report-note-header {
  background: #fff8e1;
  border-bottom-color: #e9c46a;
}
.report-note-avatar {
  align-items: center;
  background: #0969da;
  border-radius: 50%;
  color: #ffffff;
  display: inline-flex;
  font-size: 13px;
  font-weight: 600;
  height: 28px;
  justify-content: center;
  width: 28px;
}
.report-note-byline {
  color: #57606a;
  flex: 1 1 auto;
  font-size: 13px;
  min-width: 0;
}
.report-note-author {
  color: #1f2328;
  font-weight: 600;
}
.report-note-role {
  border: 1px solid transparent;
  border-radius: 2em;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.01em;
  line-height: 16px;
  margin-left: 4px;
  padding: 0 7px;
  text-transform: capitalize;
  white-space: nowrap;
}
.report-note-role-lawyer {
  background: #fff8c5;
  border-color: #d4a72c66;
  color: #7d4e00;
}
.report-note-role-admin {
  background: #ddf4ff;
  border-color: #54aeff66;
  color: #0550ae;
}
.report-note-role-user {
  background: #eaeef2;
  border-color: rgba(110, 119, 129, 0.25);
  color: #57606a;
}
.report-note-date {
  color: #57606a;
}
.report-note-permalink {
  color: #57606a;
  text-decoration: none;
}
.report-note-permalink:hover {
  color: #0969da;
  text-decoration: underline;
}
.report-note-package-link {
  color: #57606a;
  font-weight: 600;
  text-decoration: none;
}
.report-note-package-link:hover {
  color: #0969da;
  text-decoration: underline;
}
.report-note-package-name {
  color: #57606a;
  font-weight: 600;
}
.report-note-highlight {
  animation: report-note-flash 2s ease-out;
}
@keyframes report-note-flash {
  0% {
    box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.45);
  }
  100% {
    box-shadow: 0 0 0 0 rgba(9, 105, 218, 0);
  }
}
.report-note-badges {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.report-note-badge {
  border: 1px solid transparent;
  border-radius: 2em;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.01em;
  line-height: 18px;
  padding: 0 8px;
  text-transform: lowercase;
  white-space: nowrap;
}
.report-note-badge.lawyer-only-badge {
  background: #fff8c5;
  border-color: #d4a72c66;
  color: #7d4e00;
  text-transform: none;
}
.report-note-badge.ai-assisted-badge {
  background: #ddf4ff;
  border-color: #54aeff66;
  color: #0550ae;
  text-transform: none;
}
/* Origin badge: a neutral provenance link. Relevance is conveyed by the row
   (relevant = full contrast, non-relevant = de-emphasized), not the badge. */
.report-note-badge.origin-report-badge {
  background: #eaeef2;
  border-color: rgba(110, 119, 129, 0.25);
  color: #57606a;
  text-decoration: none;
  text-transform: none;
}
.report-note-badge.origin-report-badge:hover {
  background: #dde3ea;
  text-decoration: none;
}
.report-note-origin-state {
  color: #8c959f;
  font-style: italic;
}
.report-notes-toolbar {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 12px;
}
.report-notes-relevance-toggle {
  align-items: center;
  color: #1f2328;
  display: inline-flex;
  font-size: 13px;
  gap: 6px;
  margin: 0;
}
.report-notes-relevance-toggle .form-check-input {
  margin: 0;
}
.report-notes-relevance-hint {
  color: #57606a;
  font-size: 12px;
}
/* Tag chip + editor styles live in TagInput.vue (imported here), which is the
   canonical home of the tag widget and supplies these .report-note-tag* rules. */
.report-note-edit:hover:not(:disabled) {
  color: #0550ae;
}
.report-note-delete:hover:not(:disabled) {
  color: #cf222e;
}
.report-note-edited {
  color: #57606a;
  font-size: 12px;
  margin-left: 6px;
}
.report-note-separator {
  color: #57606a;
  margin: 0 4px;
}
.report-note-edit-pane {
  padding: 12px 16px;
}
.report-note-body {
  color: #1f2328;
  font-size: 14px;
  line-height: 1.5;
  padding: 14px 16px;
}
.report-note-body p:last-child {
  margin-bottom: 0;
}
.report-note-body pre {
  background: #f6f8fa;
  border-radius: 6px;
  font-size: 12px;
  overflow: auto;
  padding: 12px;
}
.report-note-body code {
  background: rgba(175, 184, 193, 0.2);
  border-radius: 4px;
  font-size: 85%;
  padding: 0.2em 0.4em;
}
.report-note-body pre code {
  background: transparent;
  padding: 0;
}
.report-note-body blockquote {
  border-left: 3px solid #d0d7de;
  color: #57606a;
  margin: 0 0 12px;
  padding-left: 12px;
}
.report-notes-sentinel {
  color: #57606a;
  font-size: 13px;
  padding: 12px 0;
  text-align: center;
}
.report-note-form {
  margin-top: 24px;
}
.report-note-form-label {
  color: #1f2328;
  display: block;
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 6px;
}
.report-note-lawyer-toggle {
  align-items: center;
  color: #57606a;
  display: inline-flex;
  font-size: 13px;
  gap: 6px;
  margin-right: auto;
}
.report-note-lawyer-toggle .form-check-input {
  margin: 0;
}
</style>
