<template>
  <LegalLoading v-if="pkgName === null" message="Reviewing package information..." />
  <div v-else>
    <div class="row">
      <div class="col-10 mt-3">
        <h2 class="report-metadata-name">
          <a :href="searchUrl" target="_blank">{{ pkgName }}</a>
          <span class="cavil-package-format-icon"
            >&nbsp;
            <i class="fa-brands fa-suse" v-if="pkgType === 'spec'"></i>
            <i class="fa-brands fa-debian" v-else-if="pkgType === 'debian'"></i>
            <i class="fa-solid fa-kiwi-bird" v-else-if="pkgType === 'kiwi'"></i>
            <i class="fa-brands fa-docker" v-else-if="pkgType === 'dockerfile'"></i>
            <i class="fa-solid fa-dharmachakra" v-else-if="pkgType === 'helm'"></i>
            <i class="fa-solid fa-industry" v-else-if="pkgType === 'obsprj'"></i>
            <i class="fa-regular fa-circle-question" v-else></i>
          </span>
        </h2>
        <dl class="report-metadata-list">
          <template v-if="pkgLicense !== null && pkgLicense.name !== null">
            <dt>License</dt>
            <dd id="pkg-license">
              {{ pkgLicense.name }}
              <small v-if="pkgLicense.spdx === false">(not SPDX)</small>
            </dd>
          </template>
          <dt>Embargoed</dt>
          <dd v-if="pkgEmbargoed === true" id="pkg-embargoed">
            <span class="badge text-bg-warning embargo-status-badge" title="Package is embargoed">
              <i class="fa-solid fa-lock" aria-hidden="true"></i>
              Yes
            </span>
          </dd>
          <dd v-else id="pkg-embargoed">No</dd>
          <template v-if="state !== null">
            <dt>State</dt>
            <dd id="pkg-state">
              <span class="badge" :class="stateBadgeClass">{{ state }}</span>
            </dd>
          </template>
          <dt>Package ID</dt>
          <dd>
            <copyable-text
              :value="String(pkgId)"
              class="report-metadata-id"
              title="Click to copy package ID"
              id="pkg-id"
              >#{{ pkgId }}</copyable-text
            >
          </dd>
          <template v-if="pkgFiles.length > 0">
            <dt>Package files</dt>
            <dd id="num-spec-files">
              <a href="#spec-files" class="report-metadata-collapse-link" data-bs-toggle="collapse">
                <span v-if="pkgFiles.length === 1">1 file</span>
                <span v-else>{{ pkgFiles.length }} files</span>
              </a>
            </dd>
          </template>
          <template v-if="actions.length > 0">
            <dt>Actions</dt>
            <dd>
              <a href="#actions" class="report-metadata-collapse-link" data-bs-toggle="collapse">
                <span v-if="actions.length === 1">1 related review</span>
                <span v-else>{{ actions.length }} related reviews</span>
              </a>
            </dd>
          </template>
          <template v-if="externalLink !== null">
            <dt>Link</dt>
            <dd><ExternalLink :link="externalLink" /></dd>
          </template>
          <template v-if="requests.length > 0">
            <dt>Requests</dt>
            <dd>
              <span v-for="(request, index) in requests" :key="index">
                <span v-if="index > 0">, </span>
                <ExternalLink :link="request" />
              </span>
            </dd>
          </template>
          <template v-if="productsHtml !== null">
            <dt>Products</dt>
            <dd v-html="productsHtml"></dd>
          </template>
          <template v-if="pkgVersion !== null">
            <dt>Version</dt>
            <dd id="pkg-version">{{ pkgVersion }}</dd>
          </template>
          <template v-if="pkgSummary !== null">
            <dt>Summary</dt>
            <dd id="pkg-summary">{{ pkgSummary }}</dd>
          </template>
          <template v-if="pkgGroup !== null">
            <dt>Group</dt>
            <dd id="pkg-group">{{ pkgGroup }}</dd>
          </template>
          <template v-if="pkgUrl !== null">
            <dt>URL</dt>
            <dd id="pkg-url">
              <a :href="pkgUrl" target="_blank">{{ pkgUrl }}</a>
            </dd>
          </template>
          <dt>Documents</dt>
          <dd id="report-documents">
            <report-documents :pkg-id="pkgId" :documents="derivedDocuments" @error="notifyError" />
          </dd>
          <template v-if="pkgShortname !== null">
            <dt>Shortname</dt>
            <dd id="pkg-shortname">{{ pkgShortname }}</dd>
          </template>
          <template v-if="checkoutUrl !== null">
            <dt>Checkout</dt>
            <dd id="checkout-url">
              <a :href="checkoutUrl" target="_blank">{{ pkgChecksum }}</a>
            </dd>
          </template>
          <template v-if="unpackedFiles > 0">
            <dt>Unpacked</dt>
            <dd id="unpacked-files">
              {{ unpackedFilesLabel }}
              <small>{{ unpackedSize }}</small>
            </dd>
          </template>
          <template v-if="pkgPriority !== null">
            <dt>Priority</dt>
            <dd id="pkg-priority">{{ pkgPriority }}</dd>
          </template>
          <template v-if="created !== null">
            <dt>Created</dt>
            <dd class="from-now">{{ created }}</dd>
          </template>
          <template v-if="reviewed !== null">
            <dt>Reviewed</dt>
            <dd class="from-now">{{ reviewed }}</dd>
          </template>
          <template v-if="reviewingUser !== null">
            <dt>Reviewing user</dt>
            <dd>
              {{ reviewingUser }}
              <span v-if="pkgAiAssisted" class="ai-assisted-badge"
                >(with AI Assistant <i class="fa-solid fa-robot"></i>)</span
              >
            </dd>
          </template>
        </dl>
      </div>
      <div class="col-2">
        <div v-if="pkgRisk !== null" class="cavil-ribbon float-end" :class="ribbonColor">
          <div class="cavil-ribbon-risk">{{ pkgRisk }}</div>
          <div class="cavil-ribbon-description">{{ ribbonDescription }}</div>
        </div>
      </div>
    </div>
    <div v-if="actions.length > 0" class="collapse" id="actions">
      <div class="metadata-collapse-inner">
        <ul class="metadata-related-list">
          <li v-for="action in actions" :key="action.id" class="metadata-related-item">
            <span class="metadata-related-name">{{ action.name }}</span>
            <span class="metadata-related-pill">{{ action.result }}</span>
            <span class="metadata-related-pill">{{ action.state }}</span>
            <span class="metadata-related-user">{{ action.reviewing_user }}</span>
            <a :href="action.actionUrl" class="metadata-related-date" target="_blank">{{ action.created }}</a>
          </li>
        </ul>
      </div>
    </div>
    <div v-if="pkgFiles.length > 0" id="spec-files" class="collapse">
      <div class="metadata-collapse-inner">
        <ul class="metadata-file-list">
          <li v-for="file in pkgFiles" :key="file.file" class="metadata-file-item">
            <h3 class="metadata-file-title">
              <i class="fa-solid fa-file-lines"></i>
              <a :href="file.fileUrl" target="_blank" rel="noopener">{{ file.file }}</a>
            </h3>
            <dl class="metadata-file-details">
              <template v-if="file.licenses !== null">
                <dt>Licenses</dt>
                <dd>{{ file.licenses }}</dd>
              </template>
              <template v-if="file.version !== null">
                <dt>Version</dt>
                <dd>{{ file.version }}</dd>
              </template>
              <template v-if="file.summary !== null">
                <dt>Summary</dt>
                <dd>{{ file.summary }}</dd>
              </template>
              <template v-if="file.group !== null">
                <dt>Group</dt>
                <dd>{{ file.group }}</dd>
              </template>
              <template v-if="file.url !== null">
                <dt>URL</dt>
                <dd>
                  <a :href="file.url" target="_blank">{{ file.url }}</a>
                </dd>
              </template>
              <template v-if="file.sources !== null">
                <dt>Sources</dt>
                <dd>{{ file.sources }}</dd>
              </template>
            </dl>
          </li>
        </ul>
      </div>
    </div>
    <section v-if="notice !== null" id="review-information" class="review-information-card">
      <header class="review-information-card-bar">
        <i class="fa-solid fa-caret-right"></i>
        <span>why this needs review</span>
      </header>
      <!-- prettier-ignore -->
      <pre class="review-information-card-body"><span
        v-for="(segment, index) in noticeSegments"
        :key="index"
      ><a
        v-if="segment.isReportId"
        :href="`/reviews/details/${segment.text}`"
        target="_blank"
        rel="noopener"
      >{{ segment.text }}</a><template v-else>{{ segment.text }}</template></span></pre>
    </section>
    <cavil-notice-panel
      v-if="errors.length > 0"
      id="spec-errors"
      icon="fa-solid fa-triangle-exclamation"
      :items="errors"
      title="Package file warnings"
      tone="warning"
    />
    <cavil-notice-panel
      v-if="legalReviewNotices.length > 0"
      id="spec-legal-review-notices"
      icon="fa-solid fa-scale-balanced"
      :items="legalReviewNotices"
      title="Legal review notices"
      tone="success"
    />
    <div class="metadata-review-section">
      <form class="container metadata-review-form" id="pkg-review" @submit.prevent>
        <div class="col metadata-review-editor">
          <CommentEditor
            ref="commentEditor"
            v-model="result"
            label="Comment"
            :placeholder="canReview ? 'Reviewed ok' : ''"
            :read-only="!canReview"
          >
            <template #actions v-if="canReview && templates.length > 0">
              <TemplatePicker
                :manage-url="hasAdminRole === true ? manageTemplatesUrl : null"
                :templates="templates"
                @select="insertTemplate"
              />
            </template>
          </CommentEditor>
        </div>
        <div v-if="canReview" class="col mb-3 metadata-review-actions">
          <div class="metadata-review-actions-group">
            <!-- One accept button; the server derives acceptable vs acceptable_by_lawyer from the
                 reviewer's capability, so a non-lawyer can never post a lawyer sign-off.

                 The pair doubles as a live indicator of the current decision: the button matching the
                 stored state carries a check and stays solid, the alternative recedes to an outline but
                 stays fully clickable so the reviewer can still switch their mind. -->
            <button
              v-for="button in reviewButtons"
              :key="button.id"
              type="button"
              :class="[
                'btn',
                buttonClass(button),
                {'is-decision-current': selectedButtonId === button.id, 'is-decision-flash': flashId === button.id}
              ]"
              :id="button.id"
              :name="button.id"
              :disabled="submitting"
              @click="submitReview(submitUrl, button.id)"
            >
              <i v-if="submittingId === button.id" class="fa-solid fa-rotate fa-spin" aria-hidden="true"></i>
              <i v-else-if="selectedButtonId === button.id" class="fa-solid fa-circle-check" aria-hidden="true"></i>
              {{ button.label }}
            </button>
          </div>
          <button
            v-if="hasAdminRole === true"
            type="button"
            :class="['btn', reindexBtnVariant, 'metadata-review-actions-secondary']"
            :title="reindexTitle"
            :disabled="reindexBusy || rebuildPending"
            id="reindex_button"
            @click="reindex"
          >
            <i v-if="reindexBusy || rebuildPending" class="fa-solid fa-rotate fa-spin" aria-hidden="true"></i>
            {{ reindexBusy || rebuildPending ? 'Reindexing…' : 'Reindex' }}
          </button>
        </div>
      </form>
    </div>
    <cavil-notice-panel
      v-if="documents.length > 0"
      id="legal-documents"
      icon="fa-solid fa-scale-balanced"
      title="Legal documents"
      :note="documentsDropped > 0 ? `${count(documentsDropped)} more not listed` : null"
    >
      <ul class="cavil-notice-list">
        <li v-for="document in documents" :key="document.path" class="cavil-notice-item legal-document-item">
          <a :href="document.url" target="_blank" rel="noopener" class="legal-document-path"
            ><FilePath :path="document.path"
          /></a>
          <span class="legal-document-lines" :title="documentShare(document)">
            <!-- Absolute, not a percentage: 15 novel lines in a 312-line BSD file round away to "5%" -->
            <span class="legal-document-tally">{{ documentTally(document) }}</span>
            <span class="legal-document-meter" aria-hidden="true"
              ><i
                v-for="block in 5"
                :key="block"
                :class="['legal-document-block', {'is-covered': block <= documentBlocks(document)}]"
              ></i
            ></span>
          </span>
        </li>
      </ul>
    </cavil-notice-panel>
    <cavil-notice-panel
      v-if="copiedFiles['%doc'] !== null || copiedFiles['%license'] !== null"
      icon="fa-regular fa-copy"
      title="Copied files"
    >
      <dl class="cavil-notice-definition-list">
        <template v-if="copiedFiles['%doc'] !== null">
          <dt>%doc</dt>
          <dd>{{ copiedFiles['%doc'] }}</dd>
        </template>
        <template v-if="copiedFiles['%license'] !== null">
          <dt>%license</dt>
          <dd>{{ copiedFiles['%license'] }}</dd>
        </template>
      </dl>
    </cavil-notice-panel>
    <ToastNotifier ref="toaster" />
  </div>
</template>

<script>
import CavilNoticePanel from './CavilNoticePanel.vue';
import CommentEditor from './CommentEditor.vue';
import CopyableText from './CopyableText.vue';
import ExternalLink from './ExternalLink.vue';
import FilePath from './FilePath.vue';
import LegalLoading from './LegalLoading.vue';
import ReportDocuments from './ReportDocuments.vue';
import TemplatePicker from './TemplatePicker.vue';
import ToastNotifier from './ToastNotifier.vue';
import {fileViewUrl, productLink} from '../helpers/links.js';
import {findPlaceholders} from '../helpers/placeholders.js';
import Refresh from '../mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'ReportMetadata',
  components: {
    CavilNoticePanel,
    CommentEditor,
    CopyableText,
    ExternalLink,
    FilePath,
    LegalLoading,
    ReportDocuments,
    TemplatePicker,
    ToastNotifier
  },
  mixins: [Refresh],
  emits: ['reindex-queued'],
  data() {
    return {
      actions: [],
      checkoutUrl: null,
      copiedFiles: {'%doc': null, '%license': null},
      created: null,
      legalDocuments: null,
      errors: [],
      externalLink: null,
      fasttrackUrl: `/reviews/fasttrack_package/${this.pkgId}`,
      legalReviewNotices: [],
      manageTemplatesUrl: '/comment-templates',
      notice: null,
      pkgAiAssisted: false,
      pkgChecksum: null,
      pkgEmbargoed: false,
      pkgFiles: [],
      pkgGroup: null,
      pkgLicense: null,
      pkgName: null,
      pkgPriority: null,
      pkgRisk: null,
      pkgShortname: null,
      pkgSummary: null,
      pkgType: null,
      pkgUrl: null,
      pkgVersion: null,
      productsHtml: null,
      refreshDelay: 30000,
      refreshUrl: `/reviews/meta/${this.pkgId}`,

      // Seeded from the page render so the button has an answer before the first refresh lands, and kept
      // current from there on: a rebuild takes the package past the patterns that lit it up, and patterns
      // created while the page sits open light it up again
      newPatterns: this.shouldReindex,
      reindexBusy: false,
      reindexFailed: false,
      reindexing: false,
      reindexQueued: false,
      requests: [],
      result: '',
      reviewed: null,
      reviewingUser: null,
      reviewUrl: `/reviews/review_package/${this.pkgId}`,
      searchUrl: null,
      derivedDocuments: null,
      state: null,
      submitting: false,
      submittingId: null,
      flashId: null,
      flashTimer: null,
      templates: [],
      unpackedFiles: 0,
      unpackedSize: 'n/a'
    };
  },
  computed: {
    canReview() {
      return this.hasAdminRole === true || this.hasManagerRole === true;
    },

    documents() {
      return this.legalDocuments?.documents ?? [];
    },

    documentsDropped() {
      return this.legalDocuments?.dropped ?? 0;
    },

    // A curator gets accept and reject, a manager only the fasttrack accept
    reviewButtons() {
      if (this.hasAdminRole === true) {
        return [
          {id: 'acceptable', variant: 'btn-success', label: this.hasLawyerRole ? 'Acceptable by Lawyer' : 'Acceptable'},
          {id: 'unacceptable', variant: 'btn-danger', label: 'Unacceptable'}
        ];
      }
      if (this.hasManagerRole === true) return [{id: 'acceptable', variant: 'btn-success', label: 'Acceptable'}];
      return [];
    },
    submitUrl() {
      return this.hasAdminRole === true ? this.reviewUrl : this.fasttrackUrl;
    },
    // Which review button the stored state currently corresponds to (null while the package is still
    // "new"), so the pair can show the decision instead of just firing it
    selectedButtonId() {
      if (this.state === 'acceptable' || this.state === 'acceptable_by_lawyer') return 'acceptable';
      if (this.state === 'unacceptable') return 'unacceptable';
      return null;
    },
    // Notices that compare against an older review name it by id ("Diff to
    // closest match 538922", "Not found any significant difference against
    // 538922"). Those ids become links to that report, everything else stays
    // plain text.
    noticeSegments() {
      if (this.notice === null) return [];
      const segments = [];
      const pattern = /(?<=Diff to closest match |significant difference against )\d+/g;
      let plainFrom = 0;
      for (const match of this.notice.matchAll(pattern)) {
        segments.push({text: this.notice.slice(plainFrom, match.index)});
        segments.push({text: match[0], isReportId: true});
        plainFrom = match.index + match[0].length;
      }
      segments.push({text: this.notice.slice(plainFrom)});
      return segments;
    },
    unpackedFilesWithSeparator() {
      return this.unpackedFiles.toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    },

    // The count on its own, so the size can sit beside it as a quiet aside instead of in brackets
    unpackedFilesLabel() {
      return this.unpackedFiles === 1 ? '1 file' : `${this.unpackedFilesWithSeparator} files`;
    },
    ribbonColor() {
      if (this.pkgRisk === '1' || this.pkgRisk === '2' || this.pkgRisk === '3' || this.pkgRisk === '4') {
        return 'cavil-green-ribbon';
      }
      if (this.pkgRisk === '5') return 'cavil-orange-ribbon';
      if (this.pkgRisk === '6' || this.pkgRisk === '7' || this.pkgRisk === '8') return 'cavil-red-ribbon';
      return 'cavil-gray-ribbon';
    },
    ribbonDescription() {
      if (this.pkgRisk === '1') return 'Public Domain';
      if (this.pkgRisk === '2') return 'Permissive';
      if (this.pkgRisk === '3') return 'Weak Copyleft';
      if (this.pkgRisk === '4') return 'Strong Copyleft';
      if (this.pkgRisk === '5') return 'Managed Obligations';
      if (this.pkgRisk === '6') return 'Restrictive Obligations';
      if (this.pkgRisk === '7') return 'Non-Commercial';
      return 'Unknown Risk';
    },
    stateBadgeClass() {
      if (this.state === 'new') return 'text-bg-secondary';
      if (this.state === 'acceptable_by_lawyer' || this.state === 'acceptable') return 'text-bg-success';
      return 'text-bg-danger';
    },
    // A rebuild that is already on its way answers the button, so it stops advertising the patterns that
    // rebuild is about to pick up - whoever started it
    rebuildPending() {
      return this.reindexQueued || this.reindexing;
    },
    reindexBtnVariant() {
      if (this.reindexFailed) return 'btn-outline-danger';
      if (this.rebuildPending) return 'btn-outline-secondary';
      return this.newPatterns ? 'btn-outline-primary' : 'btn-outline-secondary';
    },
    reindexTitle() {
      if (this.reindexFailed) return 'Reindex request failed';
      if (this.rebuildPending) return 'Reindex has been requested';
      return this.newPatterns ? 'There are new patterns!' : 'There are no new patterns';
    }
  },
  // Templates barely ever change, so they are fetched once instead of on every metadata refresh
  mounted() {
    if (this.canReview) this.loadTemplates();
  },
  methods: {
    insertTemplate(template) {
      this.$refs.commentEditor?.insertTemplate(template.body);
    },

    // Never zero and never full below 100%: the case this exists for is a few lines in a large file
    // Filled is coverage, the direction every other meter in the world fills. Marking the deficit
    // instead put amber on the rows that needed reading and lawyers could not decode it.
    documentBlocks(document) {
      if (document.unexplained >= document.lines) return 0;
      return 5 - Math.min(4, Math.ceil((document.unexplained / document.lines) * 5));
    },

    // One annotation on the mark rather than two aligned columns, now that the mark is what gets scanned.
    // Counts recognised lines, the same direction the blocks fill, or the two halves of the row disagree.
    documentTally(document) {
      const recognised = document.lines - document.unexplained;
      if (document.unexplained > 0) return `${this.count(recognised)} of ${this.count(document.lines)} lines`;
      return `${this.count(document.lines)} ${document.lines === 1 ? 'line' : 'lines'}`;
    },

    documentShare(document) {
      const recognised = document.lines - document.unexplained;
      return `${this.count(recognised)} of ${this.count(document.lines)} lines recognised`;
    },
    // Grouped explicitly rather than by browser locale, so a line count reads the same for everyone and
    // cannot come back as "4.651" for a reader whose locale swaps the separators.
    count(number) {
      return number.toLocaleString('en-US');
    },
    // Before a decision both buttons stay solid (a plain call to action). Once one is the stored decision
    // it keeps its solid colour and the other relaxes to an outline - quieter, but still obviously a button
    // the reviewer can click to switch.
    buttonClass(button) {
      if (this.selectedButtonId === null || this.selectedButtonId === button.id) return button.variant;
      return button.variant.replace('btn-', 'btn-outline-');
    },
    // A short one-shot pulse on the button that just became the decision, so a change registers right where
    // the cursor is even when accept/reject are toggled back and forth
    flashDecision(id) {
      if (id === null) return;
      if (this.flashTimer !== null) clearTimeout(this.flashTimer);
      this.flashId = null;
      this.$nextTick(() => {
        this.flashId = id;
        this.flashTimer = setTimeout(() => {
          this.flashId = null;
          this.flashTimer = null;
        }, 900);
      });
    },
    async loadTemplates() {
      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.get('/comment-templates/all');
        if (res.isSuccess) this.templates = await res.json();
      } catch (err) {
        // Not being able to offer templates is no reason to bother the reviewer, the picker just stays hidden
      }
    },
    // The decision is posted as the form field the server expects ("acceptable"/"unacceptable"), but which
    // state that turns into is still derived server side from the reviewer's capability
    async submitReview(url, decision) {
      if (this.submitting) return;

      // A leftover placeholder is occasionally intentional, so this warns rather than blocks
      const unfilled = findPlaceholders(this.result);
      if (unfilled.length > 0) {
        const tokens = unfilled.map(p => p.name).join(', ');
        if (!window.confirm(`The comment still contains unfilled placeholders: ${tokens}. Submit anyway?`)) return;
      }

      this.submitting = true;
      this.submittingId = decision;

      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.post(url, {form: {comment: this.result, [decision]: 1}});

        let data = null;
        try {
          data = await res.json();
        } catch (e) {
          // Not JSON, an authentication failure renders an HTML page
        }

        if (res.isSuccess && data && data.ok) {
          this.$refs.toaster?.notify(`Reviewed ${data.name} as ${data.state}`);

          // Do not race the pending refresh timer, and do not update the state optimistically, the
          // stale local state is what makes refreshData() adopt the comment the server just stored
          this.cancelApiRefresh();
          await this.doApiRefresh();

          // The refresh has flipped the selected button, now pulse it so the change is unmissable
          this.flashDecision(this.selectedButtonId);
          return;
        }

        const message = (data && data.error) || `Request failed (HTTP ${res.statusCode})`;
        this.$refs.toaster?.notify(message, 'danger', 5000);
      } catch (err) {
        this.$refs.toaster?.notify(`Review request failed: ${err}`, 'danger', 5000);
      } finally {
        this.submitting = false;
        this.submittingId = null;
      }
    },
    notifyError(message) {
      this.$refs.toaster?.notify(message, 'danger', 5000);
    },

    // The rebuild happens next to the report the reviewer is reading, so there is nothing to reload here.
    // The report area is told to enter its rebuild state instead, and the notice appearing under the
    // metadata is what confirms the click.
    async reindex() {
      this.reindexBusy = true;
      this.reindexFailed = false;
      try {
        const response = await fetch(this.reindexUrl, {method: 'POST', cache: 'no-store'});
        if (response.ok) {
          this.reindexBusy = false;
          this.reindexQueued = true;
          this.$emit('reindex-queued');
          return;
        }
      } catch (err) {
        console.error('Reindex request failed:', err);
      }
      this.reindexBusy = false;
      this.reindexFailed = true;
    },

    // The report area has swapped in the new report, which is the moment the button's answer changes.
    // Waiting for the next scheduled refresh would leave it advertising patterns that are already in.
    rebuildFinished() {
      this.reindexQueued = false;
      this.cancelApiRefresh();
      return this.doApiRefresh();
    },
    refreshData(data) {
      const copiedFiles = data.copied_files;
      if (copiedFiles['%doc'].length > 0) this.copiedFiles['%doc'] = copiedFiles['%doc'].join(' ');
      if (copiedFiles['%license'].length > 0) this.copiedFiles['%license'] = copiedFiles['%license'].join(' ');

      this.created = moment(data.created * 1000).fromNow();
      this.legalDocuments = data.legal_documents ?? null;
      this.errors = data.errors;
      this.externalLink = data.external_link_data ?? data.external_link;
      this.derivedDocuments = data.documents;
      this.legalReviewNotices = data.legal_review_notices;

      this.actions = data.actions;
      for (const action of this.actions) {
        action.created = moment(action.created * 1000).fromNow();
        action.actionUrl = `/reviews/details/${action.id}`;
      }

      this.pkgFiles = data.package_files;
      for (const file of this.pkgFiles) {
        file.fileUrl = fileViewUrl(this.pkgId, file.file);
        file.licenses = file.licenses.length > 0 ? file.licenses.join(', ') : null;
        file.sources = file.sources.length > 0 ? file.sources.join(', ') : null;
      }

      this.pkgGroup = data.package_group;
      this.pkgLicense = data.package_license;
      this.pkgName = data.package_name;
      this.pkgPriority = data.package_priority;
      this.pkgRisk = data.package_risk;
      this.pkgShortname = data.package_shortname;
      this.pkgSummary = data.package_summary;
      this.pkgType = data.package_type;
      this.pkgUrl = data.package_url;
      this.pkgVersion = data.package_version;
      this.pkgEmbargoed = data.embargoed;
      this.pkgAiAssisted = data.ai_assisted;

      this.pkgChecksum = data.package_checksum;
      this.checkoutUrl = `/reviews/file_view/${this.pkgId}`;

      this.newPatterns = data.should_reindex;
      this.reindexing = data.reindexing;

      if (data.products.length > 0) {
        this.productsHtml = data.products.map(name => productLink({name}, {blank: true})).join(', ');
      }
      this.requests = [];
      if (data.requests.length > 0) {
        this.requests = data.requests_data ?? data.requests;
      }

      if (data.reviewed !== null) this.reviewed = moment(data.reviewed * 1000).fromNow();
      this.reviewingUser = data.reviewing_user;
      this.searchUrl = `/search?q=${this.pkgName}`;

      // Make sure not to reset the comment field in the middle of a review (unless someone else changed the state)
      if (data.state !== this.state) this.result = data.result ?? '';
      this.notice = data.notice;
      this.state = data.state;

      if (data.unpacked_files !== null) {
        this.unpackedFiles = data.unpacked_files;
        this.unpackedSize = data.unpacked_size;
      }
    }
  }
};
</script>

<style>
.report-metadata-name {
  font-weight: 500;
  letter-spacing: -0.01em;
  margin-bottom: 1.1rem;
}
.report-metadata-list {
  color: var(--cavil-fg);
  display: grid;
  font-feature-settings: 'liga', 'kern';
  font-size: 15px;
  font-variant-numeric: tabular-nums;
  gap: 0.6rem 1.75rem;
  grid-template-columns: max-content minmax(0, 1fr);
  line-height: 1.55;
  margin: 0;
}
.report-metadata-list dt {
  color: var(--cavil-fg-subtle);
  font-size: 13px;
  font-weight: 500;
  letter-spacing: 0.02em;
  padding-top: 0.12rem;
  text-transform: uppercase;
}
.report-metadata-list dd {
  margin: 0;
  min-width: 0;
  overflow-wrap: anywhere;
}
.report-metadata-list a:not(.cavil-external-link-target) {
  color: var(--cavil-accent);
  text-decoration: none;
  text-underline-offset: 2px;
}
.report-metadata-list a:not(.cavil-external-link-target):hover,
.report-metadata-list a:not(.cavil-external-link-target):focus {
  text-decoration: underline;
}
.report-metadata-list small {
  color: var(--cavil-fg-disabled);
  font-size: 12px;
  font-weight: 400;
}
.report-metadata-list .badge {
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.01em;
  padding: 0.4em 0.65em;
  vertical-align: baseline;
}
.embargo-status-badge {
  align-items: center;
  display: inline-flex;
  gap: 0.35rem;
}
.report-metadata-id {
  border-radius: 6px;
  color: var(--cavil-fg);
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 14px;
  padding: 0.05rem 0.35rem;
  transition:
    background-color 0.15s ease,
    color 0.15s ease;
}
.report-metadata-id:hover,
.report-metadata-id:focus {
  background: var(--cavil-canvas-subtle);
  color: var(--cavil-accent);
  outline: none;
}
.report-metadata-collapse-link {
  border-bottom: 1px dashed var(--cavil-border-strong);
}
.report-metadata-collapse-link:hover,
.report-metadata-collapse-link:focus {
  border-bottom-color: transparent;
}
#pkg-shortname,
#checkout-url a,
#pkg-version,
#pkg-priority {
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 14px;
}
@media (max-width: 700px) {
  .report-metadata-list {
    grid-template-columns: 1fr;
    gap: 0.25rem 0;
  }
  .report-metadata-list dd {
    margin-bottom: 0.45rem;
  }
}
.metadata-count-pill {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
  display: inline-flex;
  font-size: 12px;
  font-weight: 600;
  line-height: 1;
  padding: 0.35rem 0.6rem;
  text-decoration: none;
  white-space: nowrap;
}
.metadata-count-pill:hover,
.metadata-count-pill:focus {
  background: var(--cavil-accent-tint-1);
  border-color: var(--cavil-accent-border);
  color: var(--cavil-accent);
  text-decoration: none;
}
.cavil-notice-item.legal-document-item {
  align-items: baseline;
  background: linear-gradient(90deg, rgba(var(--cavil-success-rgb), 0.08), var(--cavil-canvas) 2.5rem);
  display: flex;
  gap: 0.85rem;
  white-space: normal;
}
.cavil-notice-item.legal-document-item:hover {
  background: linear-gradient(90deg, rgba(var(--cavil-success-rgb), 0.12), var(--cavil-canvas-subtle) 2.5rem);
}
/* A wash needs a light canvas to read as a tint; over near-black it only ever comes out as
   grey haze. Dark marks the row the way the risk bands already do, with a thin inset rule. */
[data-bs-theme='dark'] .cavil-notice-item.legal-document-item {
  background: var(--cavil-canvas);
  box-shadow: inset 2px 0 0 var(--cavil-success-emphasis);
}
[data-bs-theme='dark'] .cavil-notice-item.legal-document-item:hover {
  background: var(--cavil-canvas-subtle);
}
/* File names follow the report's convention: muted until hovered, where they turn link-blue */
.legal-document-path {
  color: var(--cavil-fg-muted);
  flex: 1 1 auto;
  font-size: 13px;
  font-weight: 500;
  line-height: 1.35;
  min-width: 0;
  overflow-wrap: anywhere;
  text-decoration-color: transparent;
}
.legal-document-path:hover,
.legal-document-path:focus {
  color: var(--cavil-accent-strong);
  text-decoration-color: currentColor;
}
.legal-document-lines {
  /* The mark has no text of its own, so its baseline is its bottom edge: it sits on the annotation's
     baseline, where it sat when it was part of that text run. Stretch would hang it from the top. */
  align-items: baseline;
  color: var(--cavil-fg-subtle);
  display: flex;
  flex: 0 0 auto;
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  gap: 0.6rem;
  white-space: nowrap;
}
/* GitHub's diffstat mark: proportion beside the count, never instead of it. Amber rather than red, which
   would grade text that is only unmatched, and green/red is the one pair some readers cannot separate.
   A covered file marks five greys rather than nothing, which is what amber is read against. */
.legal-document-meter {
  display: inline-flex;
  gap: 2px;
}
.legal-document-block {
  background: var(--cavil-border);
  border-radius: 1px;
  height: 8px;
  width: 8px;
}
.legal-document-block.is-covered {
  background: var(--cavil-success);
}
.metadata-collapse-inner {
  padding: 0.85rem 0 1.1rem;
}
.metadata-related-list,
.metadata-file-list {
  list-style: none;
  margin: 0;
  padding: 0;
}
.metadata-related-item {
  align-items: center;
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 8px;
  display: grid;
  gap: 0.75rem;
  grid-template-columns: minmax(0, 1fr) auto auto minmax(120px, auto) auto;
  margin-bottom: 0.75rem;
  overflow: hidden;
  padding: 0.65rem 0.85rem;
  transition: background-color 0.15s ease;
}
.metadata-related-item:last-child {
  margin-bottom: 0;
}
.metadata-related-item:hover,
.metadata-file-item:hover {
  background: var(--cavil-canvas-subtle);
}
.metadata-related-name {
  color: var(--cavil-fg);
  font-size: 13px;
  font-weight: 600;
  min-width: 0;
  overflow-wrap: anywhere;
}
.metadata-related-pill {
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
  font-size: 12px;
  font-weight: 600;
  line-height: 1;
  padding: 0.35rem 0.6rem;
  white-space: nowrap;
}
.metadata-related-user,
.metadata-related-date {
  color: var(--cavil-fg-muted);
  font-size: 13px;
  min-width: 0;
  overflow-wrap: anywhere;
}
.metadata-related-date {
  justify-self: end;
  text-decoration-color: transparent;
  white-space: nowrap;
}
.metadata-related-date:hover,
.metadata-related-date:focus {
  color: var(--cavil-accent-strong);
  text-decoration-color: currentColor;
}
.metadata-file-item {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 8px;
  margin-bottom: 0.85rem;
  overflow: hidden;
  transition: background-color 0.15s ease;
}
.metadata-file-item:last-child {
  margin-bottom: 0;
}
.metadata-file-title {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border);
  color: var(--cavil-fg);
  display: flex;
  font-size: 13px;
  font-weight: 600;
  gap: 0.45rem;
  line-height: 1.35;
  margin: 0;
  overflow-wrap: anywhere;
  padding: 0.65rem 0.85rem;
}
.metadata-file-title i {
  color: var(--cavil-fg-subtle);
}
.metadata-file-title a {
  color: inherit;
  text-decoration-color: transparent;
}
.metadata-file-title a:hover,
.metadata-file-title a:focus {
  color: inherit;
  text-decoration-color: currentColor;
}
.metadata-file-details {
  display: grid;
  font-size: 13px;
  gap: 0.35rem 0.85rem;
  grid-template-columns: max-content minmax(0, 1fr);
  margin: 0;
  padding: 0.75rem 0.85rem;
}
.metadata-file-details dt {
  color: var(--cavil-fg-muted);
  font-weight: 600;
}
.metadata-file-details dd {
  color: var(--cavil-fg);
  margin: 0;
  min-width: 0;
  overflow-wrap: anywhere;
}
.metadata-file-details a {
  text-decoration-color: transparent;
}
.metadata-file-details a:hover,
.metadata-file-details a:focus {
  text-decoration-color: currentColor;
}
/* Review-information card. Rendered as a terminal/console panel — a small
   dark title bar with a prompt-style caret + label, then the freeform
   monospace body as if it were tool output. Visually distinct from the
   surrounding notice stack so reviewers and packagers can't miss it,
   regardless of whether the body is a single sentence or a multi-line diff. */
.review-information-card {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-review-card-border);
  border-radius: 6px;
  margin: 1.25rem 0;
  overflow: hidden;
}
.review-information-card-bar {
  align-items: center;
  background: var(--cavil-inverse-bg-alt);
  color: var(--cavil-inverse-fg-subtle);
  display: flex;
  font-size: 12px;
  font-weight: 500;
  gap: 0.45rem;
  letter-spacing: 0.04em;
  padding: 0.45rem 0.85rem;
  text-transform: lowercase;
}
.review-information-card-bar i {
  color: var(--cavil-grey-4);
  font-size: 11px;
}
/* The compared report id links to that report, but stays typographically
   part of the tool output — only an underline on hover gives it away. */
.review-information-card-body a {
  color: inherit;
  text-decoration: none;
}
.review-information-card-body a:hover,
.review-information-card-body a:focus {
  text-decoration: underline;
}
.review-information-card-body {
  color: var(--cavil-fg);
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 13px;
  line-height: 1.55;
  margin: 0;
  overflow-x: auto;
  padding: 0.85rem 0.95rem;
  white-space: pre-wrap;
}
.metadata-review-section {
  margin: 1.25rem 0;
}
.metadata-review-form {
  padding: 0;
}
/* The bordered box, its header bar and the focus ring now belong to CommentEditor */
.metadata-review-actions {
  align-items: center;
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-top: 0.75rem;
}
.metadata-review-actions .btn {
  border-radius: 6px;
  font-size: 13px;
  font-weight: 600;
  position: relative;
}
.metadata-review-actions-group {
  align-items: center;
  display: inline-flex;
  flex-wrap: wrap;
}
.metadata-review-actions-group > span {
  display: inline-flex;
}
.metadata-review-actions-group > * + * {
  margin-left: -1px;
}
.metadata-review-actions-group > *:not(:first-child) .btn,
.metadata-review-actions-group > .btn:not(:first-child) {
  border-bottom-left-radius: 0;
  border-top-left-radius: 0;
}
.metadata-review-actions-group > *:not(:last-child) .btn,
.metadata-review-actions-group > .btn:not(:last-child) {
  border-bottom-right-radius: 0;
  border-top-right-radius: 0;
}
.metadata-review-actions .btn:hover,
.metadata-review-actions .btn:focus {
  z-index: 1;
}
.metadata-review-actions .btn i {
  margin-right: 0.4em;
}
/* The button that reflects the stored decision keeps its solid fill and sits above its outlined
   neighbour so its border reads as a single unbroken segment */
.metadata-review-actions .btn.is-decision-current {
  z-index: 1;
}
/* One-shot pulse when a decision is made or switched, drawing the eye to the button under the cursor */
.metadata-review-actions .btn.is-decision-flash {
  animation: metadata-decision-flash 0.7s ease;
}
@keyframes metadata-decision-flash {
  0% {
    filter: brightness(1);
  }
  35% {
    filter: brightness(1.4);
  }
  100% {
    filter: brightness(1);
  }
}
@media (prefers-reduced-motion: reduce) {
  .metadata-review-actions .btn.is-decision-flash {
    animation: none;
  }
}
.metadata-review-actions-secondary {
  margin-left: auto;
}
@media (max-width: 900px) {
  .metadata-related-item {
    align-items: flex-start;
    grid-template-columns: 1fr;
  }
  .metadata-related-date {
    justify-self: start;
  }
}
@media (max-width: 700px) {
  .metadata-file-details {
    grid-template-columns: 1fr;
  }
  .metadata-file-details dd + dt {
    margin-top: 0.25rem;
  }
}
.cavil-classification-badge {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 0.5rem;
  border-radius: 1rem;
  background-color: var(--cavil-accent-deep-2);
  color: var(--cavil-canvas);
  width: 150px;
}
.cavil-package-format-icon i {
  color: var(--cavil-fg-secondary);
}

/* The fills stay put across themes: they are saturated chips carrying white text, and the
   brighter dark-mode greens and reds would drop that below legible. The neutral one is the
   exception, because its light value inverts to a pale grey. */
.cavil-green-ribbon {
  --cavil-ribbon-bg-color: #198754;
}
.cavil-orange-ribbon {
  --cavil-ribbon-bg-color: #ffc107;
  --cavil-ribbon-color: #000;
}
.cavil-red-ribbon {
  --cavil-ribbon-bg-color: #dc3545;
}
.cavil-gray-ribbon {
  --cavil-ribbon-bg-color: var(--cavil-risk-unknown-bg);
}
/* Tinted rather than filled, matching the risk chips. The ribbon is still the loudest thing
   on the page: at this size the emphasis comes from the shape, so it does not also need a
   saturated fill, which next to the chips just read as dated. No border, because clip-path
   cuts the arrow out of the element and would cut the border with it. */
[data-bs-theme='dark'] .cavil-green-ribbon {
  --cavil-ribbon-bg-color: rgba(var(--cavil-success-rgb), 0.22);
  --cavil-ribbon-color: var(--cavil-success);
}
[data-bs-theme='dark'] .cavil-orange-ribbon {
  --cavil-ribbon-bg-color: rgba(var(--cavil-attention-border-rgb), 0.22);
  --cavil-ribbon-color: var(--cavil-attention-deep);
}
[data-bs-theme='dark'] .cavil-red-ribbon {
  --cavil-ribbon-bg-color: rgba(var(--cavil-danger-rgb), 0.22);
  --cavil-ribbon-color: var(--cavil-danger);
}
[data-bs-theme='dark'] .cavil-gray-ribbon {
  --cavil-ribbon-bg-color: var(--cavil-neutral-bg);
  --cavil-ribbon-color: var(--cavil-fg-muted);
}
.cavil-ribbon {
  color: var(--cavil-ribbon-color, var(--cavil-on-accent));
  font-family:
    system-ui,
    -apple-system,
    'Segoe UI',
    Roboto,
    'Helvetica Neue',
    'Noto Sans',
    'Liberation Sans',
    Arial,
    sans-serif,
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Segoe UI Symbol',
    'Noto Color Emoji';
  width: 110px;
}
.cavil-ribbon {
  --r: 0.8em;
  border-inline: 0.5em solid #0000;
  padding: 0.5em 0.2em calc(var(--r) + 0.2em);
  clip-path: polygon(
    0 0,
    100% 0,
    100% 100%,
    calc(100% - 0.5em) calc(100% - var(--r)),
    50% 100%,
    0.5em calc(100% - var(--r)),
    0 100%
  );
  background:
    radial-gradient(50% 0.2em at top, rgba(0, 0, 0, 0), #0000) border-box,
    var(--cavil-ribbon-bg-color) padding-box;
}

.cavil-ribbon-risk {
  font-size: 2.5rem;
  font-weight: bold;
  padding: 0.3em;
  text-align: center;
}
.cavil-ribbon-description {
  font-size: 0.7rem;
  font-weight: bold;
  padding: 0.6rem;
  text-align: center;
  word-break: break-word;
}
</style>
