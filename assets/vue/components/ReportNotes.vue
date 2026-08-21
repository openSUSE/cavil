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
      <LegalLoading message="Loading notes..." size="small" />
    </div>
    <div v-else>
      <div v-if="pinError" class="report-notes-error" data-note-pin-error>
        <i class="fa-solid fa-triangle-exclamation"></i> {{ pinError }}
      </div>
      <div v-if="allNotes.length === 0 && !loadError" class="report-notes-empty">
        <i class="fa-regular fa-note-sticky"></i>
        <p class="mb-0">{{ emptyMessage }}</p>
      </div>
      <ul v-else class="report-notes-list">
        <li
          v-for="(c, i) in allNotes"
          :key="c.id"
          :id="`note-${c.id}`"
          :class="[
            'report-note',
            {
              'report-note-lawyer-only': c.lawyer_only,
              'report-note-pinned': c.pinned,
              'report-note-pinned-last': c.pinned && i === pinnedNotes.length - 1,
              'report-note-deemphasized': isNonRelevant(c)
            }
          ]"
          :data-note-id="c.id"
        >
          <div class="report-note-header">
            <span class="report-note-avatar" :title="c.author.login">
              {{ initial(c) }}
            </span>
            <div class="report-note-byline">
              <span class="report-note-author">{{ c.author.login }}</span>
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
                v-if="c.pinned"
                class="report-note-badge pinned-badge"
                title="Pinned by a reviewer as standing context for every review of this package"
                data-note-pinned-badge
              >
                <i class="fa-solid fa-thumbtack"></i> pinned
              </span>
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
                v-if="allowActions && c.can_pin && editingId !== c.id"
                type="button"
                :class="['report-note-pin', 'cavil-icon-action', {'is-pinned': c.pinned}]"
                :disabled="pinningId === c.id"
                :title="c.pinned ? 'Unpin this note' : 'Pin this note to the top for future reviewers'"
                :data-note-pin="c.id"
                @click="togglePin(c)"
              >
                <i class="fa-solid fa-thumbtack"></i>
              </button>
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
          <div v-else class="report-note-body-wrap">
            <div class="report-note-body markdown-body" v-html="c.body_html"></div>
            <span v-if="isNonRelevant(c)" class="report-note-relevance-overlay" data-note-relevance-overlay>
              <span class="report-note-relevance-label">Not relevant to this report</span>
            </span>
          </div>
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
            <span class="report-note-composer-toggles">
              <label v-if="canPostLawyerOnly" class="report-note-composer-toggle">
                <input type="checkbox" v-model="lawyerOnly" class="form-check-input" data-note-lawyer-only />
                Lawyers only
              </label>
              <label v-if="canPin" class="report-note-composer-toggle">
                <input type="checkbox" v-model="pinned" class="form-check-input" data-note-pinned />
                Pinned
              </label>
            </span>
          </template>
        </MarkdownComposer>
      </div>
    </div>
  </div>
</template>

<script>
import LegalLoading from './LegalLoading.vue';
import MarkdownComposer from './MarkdownComposer.vue';
import TagInput from './TagInput.vue';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'ReportNotes',
  components: {LegalLoading, MarkdownComposer, TagInput},
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
    // Pinned notes are served outside the keyset stream, so they are stitched
    // back on at render time rather than sorted into it.
    allNotes() {
      return [...this.pinnedNotes, ...this.notes];
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
      pinnedNotes: [],
      hasMore: false,
      initialLoading: true,
      loadingMore: false,
      loadError: null,
      submitting: false,
      submitError: null,
      deletingId: null,
      pinningId: null,
      pinError: null,
      canPin: false,
      draft: '',
      lawyerOnly: false,
      pinned: false,
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

    // Rendered, not merely fetched: counts-changed still fires while the list is a spinner, and
    // anything scrolling to the notes needs their real height.
    await this.$nextTick();
    this.$emit('ready');
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
    // mixed list so the relevant notes stand out by contrast. A pin is a
    // reviewer saying the note applies whatever the report says, which
    // outranks the automatic judgement.
    isNonRelevant(c) {
      return this.isFromOtherReport(c) && !this.isRelevant(c) && !c.pinned;
    },
    isObsoleteOrigin(c) {
      return !!(c.original_package && c.original_package.obsolete);
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
      this.pinnedNotes = [];
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
        // Only the first page carries the pinned block.
        if (Array.isArray(data.pinned)) this.pinnedNotes = data.pinned;
        if (data.can_pin !== undefined) this.canPin = !!data.can_pin;
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
        const form = {body, lawyer_only: this.lawyerOnly ? '1' : '0', pinned: this.pinned ? '1' : '0'};
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
        // A pinned note belongs in the block above the scroll, not at the head
        // of the stream, so let the server place it.
        if (data.note.pinned) this.pinnedNotes.unshift(data.note);
        else this.notes.unshift(data.note);
        this.draft = '';
        this.lawyerOnly = false;
        this.pinned = false;
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
      while (!this.allNotes.find(c => c.id === targetId) && this.hasMore && safety-- > 0) {
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
        for (const list of [this.notes, this.pinnedNotes]) {
          const idx = list.findIndex(x => x.id === c.id);
          if (idx >= 0) list.splice(idx, 1, data.note);
        }
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
    async togglePin(c) {
      if (this.pinningId !== null) return;
      this.pinningId = c.id;
      this.pinError = null;
      try {
        const form = {pinned: c.pinned ? '0' : '1'};
        const res = await this.ua.patch(`/reviews/notes/${c.id}/pin`, {form});
        if (!res.isSuccess) {
          let msg = `Failed (HTTP ${res.statusCode})`;
          try {
            const data = await res.json();
            if (data && data.error) msg = data.error;
          } catch (_) {
            // ignore
          }
          this.pinError = msg;
          return;
        }
        // The note moves between the pinned block and the keyset stream, and
        // the two are paginated independently. Splicing it across by hand
        // risks it reappearing on the next scroll page, so reload from the top.
        this.reloadFromTop();
      } catch (err) {
        this.pinError = err.message || 'Failed to pin note';
      } finally {
        this.pinningId = null;
      }
    },
    async deleteNote(c) {
      // eslint-disable-next-line no-alert
      if (!window.confirm('Delete this note?')) return;
      this.deletingId = c.id;
      try {
        const res = await this.ua.delete(`/reviews/notes/${c.id}`);
        if (!res.isSuccess) return;
        for (const list of [this.notes, this.pinnedNotes]) {
          const idx = list.findIndex(x => x.id === c.id);
          if (idx >= 0) list.splice(idx, 1);
        }
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
  border: 1px dashed var(--cavil-border);
  border-radius: 8px;
  color: var(--cavil-fg-muted);
  display: flex;
  flex-direction: column;
  gap: 12px;
  justify-content: center;
  margin: 24px 0;
  padding: 40px 20px;
  text-align: center;
}
.report-notes-empty i {
  color: var(--cavil-border-strong);
  font-size: 28px;
}
.report-notes-error {
  align-items: center;
  background: var(--cavil-danger-bg);
  border: 1px solid var(--cavil-danger-edge);
  border-radius: 6px;
  color: var(--cavil-danger-2);
  display: flex;
  gap: 8px;
  margin: 12px 0;
  padding: 8px 12px;
}
.report-note-retry {
  background: transparent;
  border: 1px solid var(--cavil-danger);
  border-radius: 6px;
  color: var(--cavil-danger);
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
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 8px;
  margin-bottom: 16px;
  overflow: hidden;
  position: relative;
}
/* Notes inherited from a report with different licensing keep their provenance
  readable, while the body recedes behind a frosted-glass relevance marker. */
.report-note-deemphasized .report-note-body {
  filter: blur(7px);
  opacity: 0.38;
  transition:
    filter 0.15s ease,
    opacity 0.15s ease;
}
.report-note-body-wrap {
  position: relative;
}
.report-note-relevance-overlay {
  align-items: center;
  backdrop-filter: blur(2px);
  background: rgba(var(--cavil-canvas-rgb), 0.68);
  color: var(--cavil-fg-subtle);
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
  background: rgba(var(--cavil-canvas-subtle-rgb), 0.88);
  border: 1px solid rgba(var(--cavil-neutral-alt-rgb), 0.22);
  border-radius: 2em;
  box-shadow: 0 1px 2px rgba(var(--cavil-shadow-alt-rgb), 0.04);
  padding: 2px 10px;
}
.report-note-deemphasized:hover .report-note-relevance-overlay,
.report-note-deemphasized:focus-within .report-note-relevance-overlay {
  opacity: 0;
  visibility: hidden;
}
.report-note-deemphasized:hover .report-note-body,
.report-note-deemphasized:focus-within .report-note-body {
  filter: none;
  opacity: 1;
}
.report-note-lawyer-only {
  border-left: 4px solid var(--cavil-attention-strong);
  background: linear-gradient(180deg, rgba(var(--cavil-attention-tint-rgb), 0.45) 0%, var(--cavil-canvas) 60px);
}
/* Pinned notes keep the normal card shape - the left-border accent belongs to
   lawyer-only, and the two flags combine on one card. A firmer border plus the
   badge is enough to read as "held above the list". */
.report-note-pinned {
  border-color: var(--cavil-fg-disabled);
}
.report-note-pinned-last {
  margin-bottom: 28px;
}
.report-note-header {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border);
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  padding: 10px 14px;
}
.report-note-lawyer-only .report-note-header {
  background: var(--cavil-attention-tint-1);
  border-bottom-color: var(--cavil-attention-2);
}
.report-note-avatar {
  align-items: center;
  background: var(--cavil-accent-emphasis);
  border-radius: 50%;
  color: var(--cavil-on-accent);
  display: inline-flex;
  font-size: 13px;
  font-weight: 600;
  height: 28px;
  justify-content: center;
  width: 28px;
}
.report-note-byline {
  color: var(--cavil-fg-muted);
  flex: 1 1 auto;
  font-size: 13px;
  min-width: 0;
}
.report-note-author {
  color: var(--cavil-fg);
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
  background: var(--cavil-attention-bg);
  border-color: var(--cavil-attention-border);
  color: var(--cavil-attention-deep);
}
.report-note-role-admin {
  background: var(--cavil-accent-bg);
  border-color: var(--cavil-accent-vivid-fade);
  color: var(--cavil-accent-strong);
}
.report-note-role-user {
  background: var(--cavil-neutral-bg);
  border-color: rgba(var(--cavil-neutral-alt-rgb), 0.25);
  color: var(--cavil-fg-muted);
}
.report-note-date {
  color: var(--cavil-fg-muted);
}
.report-note-permalink {
  color: var(--cavil-fg-muted);
  text-decoration: none;
}
.report-note-permalink:hover {
  color: var(--cavil-accent);
  text-decoration: underline;
}
.report-note-package-link {
  color: var(--cavil-fg-muted);
  font-weight: 600;
  text-decoration: none;
}
.report-note-package-link:hover {
  color: var(--cavil-accent);
  text-decoration: underline;
}
.report-note-package-name {
  color: var(--cavil-fg-muted);
  font-weight: 600;
}
.report-note-highlight {
  animation: report-note-flash 2s ease-out;
}
@keyframes report-note-flash {
  0% {
    box-shadow: 0 0 0 3px rgba(var(--cavil-accent-rgb), 0.45);
  }
  100% {
    box-shadow: 0 0 0 0 rgba(var(--cavil-accent-rgb), 0);
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
  background: var(--cavil-attention-bg);
  border-color: var(--cavil-attention-border);
  color: var(--cavil-attention-deep);
  text-transform: none;
}
.report-note-badge.ai-assisted-badge {
  background: var(--cavil-accent-bg);
  border-color: var(--cavil-accent-vivid-fade);
  color: var(--cavil-accent-strong);
  text-transform: none;
}
.report-note-badge.pinned-badge {
  background: var(--cavil-neutral-bg);
  border-color: rgba(var(--cavil-neutral-alt-rgb), 0.35);
  color: var(--cavil-fg-muted-strong);
  text-transform: none;
}
/* Origin badge: a neutral provenance link. Relevance is conveyed by the row
   (relevant = full contrast, non-relevant = de-emphasized), not the badge. */
.report-note-badge.origin-report-badge {
  background: var(--cavil-neutral-bg);
  border-color: rgba(var(--cavil-neutral-alt-rgb), 0.25);
  color: var(--cavil-fg-muted);
  text-decoration: none;
  text-transform: none;
}
.report-note-badge.origin-report-badge:hover {
  background: var(--cavil-edge-2);
  text-decoration: none;
}
.report-note-origin-state {
  color: var(--cavil-fg-disabled);
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
  color: var(--cavil-fg);
  display: inline-flex;
  font-size: 13px;
  gap: 6px;
  margin: 0;
}
.report-notes-relevance-toggle .form-check-input {
  margin: 0;
}
.report-notes-relevance-hint {
  color: var(--cavil-fg-muted);
  font-size: 12px;
}
/* Tag chip + editor styles live in TagInput.vue (imported here), which is the
   canonical home of the tag widget and supplies these .report-note-tag* rules. */
.report-note-pin.is-pinned {
  color: var(--cavil-fg-muted-strong);
}
.report-note-pin:hover:not(:disabled) {
  color: var(--cavil-accent-strong);
}
.report-note-edit:hover:not(:disabled) {
  color: var(--cavil-accent-strong);
}
.report-note-delete:hover:not(:disabled) {
  color: var(--cavil-danger);
}
.report-note-edited {
  color: var(--cavil-fg-muted);
  font-size: 12px;
  margin-left: 6px;
}
.report-note-separator {
  color: var(--cavil-fg-muted);
  margin: 0 4px;
}
.report-note-edit-pane {
  padding: 12px 16px;
}
.report-note-body {
  color: var(--cavil-fg);
  font-size: 14px;
  line-height: 1.5;
  padding: 14px 16px;
}
.report-note-body p {
  margin-bottom: 12px;
}
.report-note-body p:last-child {
  margin-bottom: 0;
}
.report-note-body ul,
.report-note-body ol {
  margin-bottom: 16px;
  padding-left: 22px;
}
.report-note-body li + li {
  margin-top: 4px;
}
.report-note-body pre {
  background: var(--cavil-canvas-subtle);
  border-radius: 6px;
  font-size: 12px;
  overflow: auto;
  padding: 12px;
}
.report-note-body code {
  background: rgba(var(--cavil-neutral-cool-rgb), 0.2);
  border-radius: 4px;
  font-size: 85%;
  padding: 0.2em 0.4em;
}
.report-note-body pre code {
  background: transparent;
  padding: 0;
}
.report-note-body blockquote {
  border-left: 3px solid var(--cavil-border);
  color: var(--cavil-fg-muted);
  margin: 0 0 12px;
  padding-left: 12px;
}
.report-notes-sentinel {
  color: var(--cavil-fg-muted);
  font-size: 13px;
  padding: 12px 0;
  text-align: center;
}
.report-note-form {
  margin-top: 24px;
}
.report-note-form-label {
  color: var(--cavil-fg);
  display: block;
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 6px;
}
.report-note-composer-toggles {
  align-items: center;
  display: inline-flex;
  gap: 14px;
  margin-right: auto;
}
.report-note-composer-toggle {
  align-items: center;
  color: var(--cavil-fg-muted);
  display: inline-flex;
  font-size: 13px;
  gap: 6px;
  margin: 0;
}
.report-note-composer-toggle .form-check-input {
  margin: 0;
}
</style>
