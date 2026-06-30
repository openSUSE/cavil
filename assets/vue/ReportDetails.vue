<template>
  <div>
    <div class="report-tabs" role="tablist" id="report-tabs">
      <button
        type="button"
        class="report-tab"
        :class="{active: activeTab === 'review'}"
        role="tab"
        :aria-selected="activeTab === 'review'"
        data-tab="review"
        @click="setActiveTab('review')"
      >
        <i class="fa-solid fa-scale-balanced"></i> Report
      </button>
      <button
        type="button"
        class="report-tab"
        :class="{active: activeTab === 'notes'}"
        role="tab"
        :aria-selected="activeTab === 'notes'"
        data-tab="notes"
        @click="setActiveTab('notes')"
      >
        <i class="fa-regular fa-note-sticky"></i>
        Notes
        <span
          v-if="noteTotal !== null"
          :class="['report-tab-badge', {'report-tab-badge-lawyer': noteLawyerCount > 0}]"
          data-note-count
          >{{ noteTotal }}</span
        >
      </button>
    </div>
    <div class="report-tab-content">
      <div
        class="report-tab-pane"
        :class="{'is-active': activeTab === 'review'}"
        :aria-hidden="activeTab !== 'review'"
        role="tabpanel"
      >
        <CavilNoticePanel
          v-if="packageObsolete && !reportUnavailable"
          title="Obsolete report"
          tone="warning"
          icon="fa-solid fa-triangle-exclamation"
          data-obsolete-report-notice
        >
          <p class="cavil-notice-summary">This report is obsolete and might not exist anymore.</p>
        </CavilNoticePanel>
        <CavilNoticePanel
          v-if="reportUnavailable"
          title="Report unavailable"
          tone="warning"
          icon="fa-solid fa-triangle-exclamation"
          data-report-unavailable
        >
          <p class="cavil-notice-summary">
            This report is obsolete and is no longer available. Notes remain available.
          </p>
        </CavilNoticePanel>
        <div v-else-if="loading">
          <ProgressBar v-if="stage" :stage="stage" />
          <div v-else>
            <span id="ajax-status">
              <i class="fa-solid fa-spinner fa-pulse"></i>Preparing the report, this may take a moment...
            </span>
          </div>
        </div>
        <CavilNoticePanel
          v-else-if="emptyReport"
          title="No matching files"
          tone="success"
          icon="fa-solid fa-circle-check"
          data-empty-report-notice
        >
          <p class="cavil-notice-summary">No files matching any known license patterns or keywords have been found.</p>
        </CavilNoticePanel>
        <div v-else>
          <br />
          <section v-if="licenseDistribution.length > 0" id="license-chart" class="license-composition-card mb-3">
            <header class="license-composition-header">
              <h3>License composition</h3>
              <div class="license-composition-total">
                <span class="license-composition-total-value">{{ licenseChartTotal }}</span>
                <span class="license-composition-total-label">{{ licenseChartTotal === 1 ? 'file' : 'files' }}</span>
              </div>
            </header>
            <div class="license-composition-body">
              <div class="license-composition-chart">
                <svg
                  class="license-composition-donut"
                  viewBox="0 0 120 120"
                  :aria-label="licenseChartSummary"
                  role="img"
                >
                  <circle class="license-composition-donut-track" cx="60" cy="60" r="44" />
                  <circle
                    v-for="entry in licenseDistribution"
                    :key="`slice-${entry.name}`"
                    class="license-composition-slice"
                    cx="60"
                    cy="60"
                    r="44"
                    pathLength="100"
                    :stroke="entry.color"
                    :stroke-dasharray="`${entry.share} ${100 - entry.share}`"
                    :stroke-dashoffset="-entry.offset"
                    tabindex="0"
                    :aria-label="licenseChartSliceLabel(entry)"
                    @blur="hideLicenseChartTooltip"
                    @focus="showLicenseChartTooltip(entry, $event)"
                    @pointerenter="showLicenseChartTooltip(entry, $event)"
                    @pointerleave="hideLicenseChartTooltip"
                    @pointermove="moveLicenseChartTooltip($event)"
                  ></circle>
                </svg>
                <div v-if="dominantLicense" class="license-composition-chart-label">
                  <b>{{ dominantLicense.percent }}%</b>
                  <span v-html="dominantLicense.name_html"></span>
                </div>
                <div
                  v-if="licenseChartTooltip"
                  class="license-composition-tooltip"
                  :style="{left: `${licenseChartTooltip.x}px`, top: `${licenseChartTooltip.y}px`}"
                >
                  <b>{{ licenseChartTooltip.percent }}%</b>
                  <span>{{ licenseChartTooltip.name }}</span>
                </div>
              </div>
              <ol class="license-composition-list">
                <li v-for="entry in licenseDistribution" :key="entry.name" class="license-composition-item">
                  <div class="license-composition-item-header">
                    <span class="license-composition-swatch" :style="{backgroundColor: entry.color}"></span>
                    <span class="license-composition-name" v-html="entry.name_html"></span>
                    <span class="license-composition-percent">{{ entry.percent }}%</span>
                  </div>
                  <div class="license-composition-meter" aria-hidden="true">
                    <span :style="{width: `${entry.share}%`, backgroundColor: entry.color}"></span>
                  </div>
                </li>
              </ol>
            </div>
          </section>

          <CavilNoticePanel
            v-if="incompatibleLicenses.length > 0"
            id="incompatible-licenses"
            title="Elevated risk"
            tone="warning"
            icon="fa-solid fa-triangle-exclamation"
          >
            <p class="cavil-notice-summary">Package might contain incompatible licenses.</p>
            <ul class="cavil-notice-list">
              <li v-for="(match, idx) in incompatibleLicenses" :key="idx" class="cavil-notice-item">
                <span v-for="(name, i) in match.licenses" :key="name">
                  <span v-if="i > 0">, </span>
                  <a class="spdx-link" :href="spdxLicenseUrl(name)" target="_blank" rel="noopener noreferrer">{{
                    name
                  }}</a>
                </span>
              </li>
            </ul>
          </CavilNoticePanel>

          <p v-if="missedFiles.length > 0" id="incomplete-warning" class="risk-license-help-text">
            Report is incomplete, reviewers need to create new license patterns for unmatched keywords or ignore false
            positive matches. Estimated risks for each file are based on the highest risk snippet. The lower its
            similarity to existing license patterns, the higher the risk will climb above the predicted license.
          </p>

          <div v-if="missedFiles.length > 0" class="risk-license-section risk-license-section-unresolved">
            <h4 id="unmatched-files" class="risk-license-heading">
              <div class="badge cavil-risk-unknown-badge">Risk 9</div>
              <span class="risk-license-summary">
                {{ unresolvedMatches }} unresolved {{ unresolvedMatches === 1 ? 'match' : 'matches' }} across
                <span id="unmatched-count">{{ missedFiles.length }}</span>
                {{ missedFiles.length === 1 ? 'file' : 'files' }}
              </span>
            </h4>
            <div id="filelist-snippets" class="collapse show">
              <ul class="risk-license-list risk-unresolved-list">
                <li v-for="file in missedFiles" :key="file.id" class="risk-license-item risk-unresolved-item">
                  <div class="risk-unresolved-row">
                    <a
                      :href="'#file-' + file.id"
                      class="file-link risk-unresolved-file"
                      @click.prevent="onFileLinkClick(file.id)"
                      >{{ file.name }}</a
                    >
                    <span class="risk-unresolved-match">
                      <b>{{ file.match }}%</b> similarity to <b v-html="file.license_html"></b>
                    </span>
                    <span class="risk-unresolved-estimate">
                      <span>estimated</span>
                      <span :class="['badge', 'estimated-risk', estimatedRiskClass(file.max_risk)]">
                        Risk {{ file.max_risk }}
                      </span>
                    </span>
                  </div>
                </li>
              </ul>
            </div>
          </div>

          <div v-for="risk in sortedRisks" :key="risk" class="risk-license-section">
            <h4 class="risk-license-heading">
              <div :class="['badge', riskBadgeClass(risk)]">Risk {{ risk }}</div>
            </h4>
            <ul :id="'risk-' + risk" class="risk-license-list">
              <li v-for="lic in risks[risk]" :key="lic.list_id" class="risk-license-item">
                <div class="risk-license-row">
                  <span class="risk-license-name" v-html="lic.name_html"></span>
                  <a :href="'#' + lic.list_id" class="risk-license-count" data-bs-toggle="collapse">
                    {{ lic.files.length }} {{ lic.files.length === 1 ? 'file' : 'files' }}
                  </a>
                </div>
                <div v-if="lic.flags.length > 0" class="risk-license-flags" aria-label="License flags">
                  <span v-for="flag in lic.flags" :key="flag" class="risk-license-flag">
                    {{ licenseFlagLabel(flag) }}
                  </span>
                </div>
                <div :id="lic.list_id" :class="lic.list_class">
                  <ul class="risk-file-list">
                    <li v-for="file in lic.shown_files" :key="file[0]">
                      <a :href="'#file-' + file[0]" class="file-link" @click.prevent="onFileLinkClick(file[0])">
                        {{ file[1] }}
                      </a>
                    </li>
                    <li v-if="lic.more_files > 0">{{ lic.more_files }} more</li>
                  </ul>
                </div>
              </li>
            </ul>
          </div>

          <div v-if="matchingGlobs.length > 0" class="report-artifact-section">
            <h2 class="report-artifact-heading">
              <span class="report-artifact-label report-artifact-label-static">
                <i class="fa-solid fa-filter-circle-xmark"></i>
                {{ matchingGlobs.length }} ignored {{ matchingGlobs.length === 1 ? 'glob' : 'globs' }}
              </span>
            </h2>
            <ul class="report-artifact-list report-glob-list">
              <li v-for="glob in matchingGlobs" :key="glob" class="report-artifact-item report-glob-item">
                <code class="report-glob-pattern">{{ glob }}</code>
              </li>
            </ul>
          </div>

          <div v-if="files.length > 0">
            <div v-for="file in files" :key="file.id" :class="['file-container', {'d-none': !file.expanded}]">
              <a :name="'file-' + file.id"></a>
              <div class="file">
                <a href="#" :id="'expand-link-' + file.id" @click.prevent="toggleExpand(file)">{{ file.path }}</a>
                <div class="float-end file-actions">
                  <span v-if="isAdminOrContributor" class="dropdown file-action-menu">
                    <a
                      href="#"
                      :id="'file-menu-' + file.id"
                      class="file-action-link"
                      data-bs-toggle="dropdown"
                      aria-haspopup="true"
                      aria-expanded="false"
                      title="File actions"
                      aria-label="File actions"
                    >
                      <i class="fa-solid fa-ellipsis-vertical"></i>
                    </a>
                    <div class="dropdown-menu dropdown-menu-end" :aria-labelledby="'file-menu-' + file.id">
                      <a href="#" class="dropdown-item" @click.prevent="openGlobProposal(file)">
                        Propose ignore glob&hellip;
                      </a>
                    </div>
                  </span>
                  <a :href="file.file_url" target="_blank" title="Open file" aria-label="Open file">
                    <i class="fa-solid fa-up-right-from-square"></i>
                  </a>
                </div>
              </div>
              <div v-if="file.expanded" :id="'file-details-' + file.id" class="source" :data-file-id="file.id">
                <FileSource
                  v-if="file.source"
                  :lines="file.source.lines"
                  :file-id="file.id"
                  :filename="file.source.filename"
                  :packname="file.source.name"
                  :has-admin-role="hasAdminRole"
                  :has-contributor-role="hasContributorRole"
                  :pending-actions="pendingActionsForFile(file.id)"
                  :inline-editor="openInlineEditor && openInlineEditor.fileId === file.id ? openInlineEditor : null"
                  @extend="onExtend(file, $event)"
                  @open-editor="openEditor"
                  @dismiss-action="dismissAction"
                  @close-editor="closeInlineEditor"
                  @editor-submit="onEditorSubmit"
                />
              </div>
            </div>
          </div>

          <div v-if="emails.length > 0" class="report-artifact-section">
            <h2 class="report-artifact-heading">
              <a
                href="#emails"
                class="report-artifact-label collapsed"
                data-bs-toggle="collapse"
                aria-expanded="false"
                aria-controls="emails"
              >
                <i class="fa-regular fa-envelope"></i>
                {{ emails.length }} {{ emails.length === 1 ? 'Email' : 'Emails' }}
              </a>
            </h2>
            <div class="collapse" id="emails">
              <ul class="report-artifact-list">
                <li v-for="email in emails" :key="email[0]" class="report-artifact-item">
                  <span class="report-artifact-value">{{ email[0] }}</span>
                  <span class="report-artifact-source">{{ email[1] }}</span>
                </li>
              </ul>
            </div>
          </div>

          <div v-if="urls.length > 0" class="report-artifact-section">
            <h2 class="report-artifact-heading">
              <a
                href="#urls"
                class="report-artifact-label collapsed"
                data-bs-toggle="collapse"
                aria-expanded="false"
                aria-controls="urls"
              >
                <i class="fa-solid fa-link"></i>
                {{ urls.length }} {{ urls.length === 1 ? 'URL' : 'URLs' }}
              </a>
            </h2>
            <div class="collapse" id="urls">
              <ul class="report-artifact-list">
                <li v-for="url in urls" :key="url[0]" class="report-artifact-item">
                  <span class="report-artifact-value">{{ url[0] }}</span>
                  <span class="report-artifact-source">{{ url[1] }}</span>
                </li>
              </ul>
            </div>
          </div>

          <br />
        </div>
        <PendingActionsWidget v-if="isAdminOrContributor && pendingActions.length > 0" />
        <GlobProposalModal ref="globProposalModal" @submit="onGlobProposalSubmit" />
      </div>
      <div
        class="report-tab-pane"
        :class="{'is-active': activeTab === 'notes'}"
        :aria-hidden="activeTab !== 'notes'"
        id="report-notes-pane"
        role="tabpanel"
      >
        <ReportNotes
          v-if="notesMounted"
          :pkg-id="pkgId"
          :can-post-lawyer-only="canPostLawyerOnly"
          :seek-note-id="seekNoteId"
          @counts-changed="onNotesCountsChanged"
        />
      </div>
    </div>

    <div class="modal fade" id="shortcutsModal" tabindex="-1" aria-labelledby="shortcutsModalLabel" aria-hidden="true">
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title" id="shortcutsModalLabel">Keyboard shortcuts</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body shortcuts-modal-body">
            <h6 class="shortcuts-section-title">Report navigation</h6>
            <dl class="shortcuts-list">
              <div class="shortcuts-row">
                <dt>Jump to next unresolved match</dt>
                <dd><kbd>n</kbd></dd>
              </div>
              <div class="shortcuts-row">
                <dt>Jump to previous unresolved match</dt>
                <dd><kbd>p</kbd></dd>
              </div>
              <div class="shortcuts-row">
                <dt>Show this help dialog</dt>
                <dd><kbd>?</kbd></dd>
              </div>
            </dl>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import FileSource from './components/FileSource.vue';
import GlobProposalModal from './components/GlobProposalModal.vue';
import PendingActionsWidget from './components/PendingActionsWidget.vue';
import ProgressBar from './components/ProgressBar.vue';
import ReportNotes from './components/ReportNotes.vue';
import {resolveSnippetFromFile, submitSnippetDecisions} from './helpers/snippetDecisions.js';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import {Modal} from 'bootstrap';

let pendingActionIdSeq = 0;
let openEditorKeySeq = 0;
const LICENSE_CHART_COLORS = ['#0969da', '#1a7f37', '#9a6700', '#cf222e', '#8250df', '#bf3989', '#57606a', '#2da44e'];

export default {
  name: 'ReportDetails',
  components: {CavilNoticePanel, FileSource, GlobProposalModal, PendingActionsWidget, ProgressBar, ReportNotes},
  mixins: [Refresh],
  provide() {
    return {
      pendingActionsStore: {
        actions: this.pendingActions,
        add: action => this.pendingActions.push(action),
        remove: id => {
          const idx = this.pendingActions.findIndex(a => a.id === id);
          if (idx >= 0) this.pendingActions.splice(idx, 1);
        },
        clear: () => {
          this.pendingActions.splice(0, this.pendingActions.length);
        },
        edit: id => this.editAction(id),
        scrollTo: id => this.scrollToAction(id),
        submitAll: () => this.submitAllActions()
      }
    };
  },
  data() {
    return {
      chart: null,
      emails: [],
      files: [],
      incompatibleLicenses: [],
      loading: true,
      matchingGlobs: [],
      missedFiles: [],
      openInlineEditor: null,
      packageName: '',
      globProposalFileId: null,
      globProposalEditingId: null,
      pendingActions: [],
      hashHandled: false,
      activeTab: 'review',
      notesMounted: false,
      noteTotal: null,
      noteLawyerCount: 0,
      canPostLawyerOnly: false,
      packageObsolete: !!this.isObsolete,
      reportUnavailable: false,
      seekNoteId: null,
      refreshDelay: 5000,
      refreshUrl: `/reviews/report_details/${this.pkgId}`,
      risks: {},
      stage: null,
      unresolvedMatches: 0,
      urls: [],
      currentMatchId: null,
      shortcutsModal: null,
      licenseChartTooltip: null
    };
  },
  computed: {
    licenseDistribution() {
      if (this.chart === null) return [];

      const licenses = this.chart.licenses ?? [];
      const licensesHtml = this.chart.licenses_html ?? [];
      const files = (this.chart['num-files'] ?? []).map(value => Number(value));
      const total = files.reduce((sum, value) => sum + (Number.isFinite(value) ? value : 0), 0);
      if (licenses.length === 0 || total === 0) return [];

      let offset = 0;
      return licenses
        .map((name, index) => {
          const count = Number.isFinite(files[index]) ? files[index] : 0;
          const cleanName = this.normalizeChartLicenseName(name);
          return {
            name: cleanName,
            name_html: licensesHtml[index] ?? cleanName,
            files: count,
            percent: Math.round((count / total) * 100),
            share: (count / total) * 100
          };
        })
        .filter(entry => entry.files > 0)
        .sort((a, b) => b.files - a.files)
        .map((entry, index) => {
          const slice = {...entry, offset, color: LICENSE_CHART_COLORS[index % LICENSE_CHART_COLORS.length]};
          offset += entry.share;
          return slice;
        });
    },
    dominantLicense() {
      return this.licenseDistribution[0] || null;
    },
    licenseChartSummary() {
      return this.licenseDistribution.map(entry => this.licenseChartSliceLabel(entry)).join(', ');
    },
    licenseChartTotal() {
      return this.licenseDistribution.reduce((sum, entry) => sum + entry.files, 0);
    },
    sortedRisks() {
      return Object.keys(this.risks).sort((a, b) => Number(b) - Number(a));
    },
    emptyReport() {
      return this.sortedRisks.length === 0 && this.missedFiles.length === 0;
    },
    isAdminOrContributor() {
      return this.hasAdminRole || this.hasContributorRole;
    }
  },
  mounted() {
    window.addEventListener('keydown', this.handleKeydown);
    this.applyInitialNoteHash();
    this.loadInitialNoteCount();
  },
  beforeUnmount() {
    window.removeEventListener('keydown', this.handleKeydown);
    if (this.shortcutsModal) {
      this.shortcutsModal.dispose();
      this.shortcutsModal = null;
    }
  },
  methods: {
    setActiveTab(tab) {
      this.activeTab = tab;
      if (tab === 'notes') this.notesMounted = true;
    },
    applyInitialNoteHash() {
      // Permalink format: #note-<id>. Switch to the Notes tab on mount
      // so the deep link resolves before the user has to click anything.
      const m = (window.location.hash || '').match(/^#note-(\d+)$/);
      if (!m) return;
      this.seekNoteId = Number(m[1]);
      this.activeTab = 'notes';
      this.notesMounted = true;
    },
    async loadInitialNoteCount() {
      // Cheap one-shot count fetch so the tab badge appears before the user
      // clicks on Notes. Endless-scroll page fetches re-emit counts.
      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.get(`/reviews/notes/${this.pkgId}`, {query: {limit: 1}});
        if (!res.isSuccess) return;
        const data = await res.json();
        this.noteTotal = data.total;
        this.noteLawyerCount = data.lawyer_only;
        this.canPostLawyerOnly = !!data.can_lawyer_only;
      } catch (_) {
        // Silent: note count is informational.
      }
    },
    onNotesCountsChanged(payload) {
      if (typeof payload.total === 'number') this.noteTotal = payload.total;
      if (typeof payload.lawyer_only === 'number') this.noteLawyerCount = payload.lawyer_only;
      if (typeof payload.bump === 'number') {
        this.noteTotal = Math.max(0, (this.noteTotal ?? 0) + payload.bump);
      }
      if (typeof payload.lawyer_only_bump === 'number') {
        this.noteLawyerCount = Math.max(0, this.noteLawyerCount + payload.lawyer_only_bump);
      }
    },
    licenseFlagLabel(flag) {
      const labels = {
        cla: 'CLA',
        eula: 'EULA',
        export_restricted: 'Export Restricted',
        patent: 'Patent',
        trademark: 'Trademark'
      };
      return labels[flag] ?? flag.replaceAll('_', ' ');
    },
    estimatedRiskClass(risk) {
      if (risk === 9) return 'cavil-risk-unknown-badge';
      if (risk > 5) return 'text-bg-danger';
      if (risk === 5) return 'text-bg-warning';
      return 'text-bg-success';
    },
    riskBadgeClass(risk) {
      const r = Number(risk);
      if (r === 9) return 'cavil-risk-unknown-badge';
      if (r <= 4) return 'text-bg-success';
      if (r === 5) return 'text-bg-warning';
      return 'text-bg-danger';
    },
    spdxLicenseUrl(name) {
      return `https://spdx.org/licenses/${encodeURIComponent(name)}.html`;
    },
    refreshData(data) {
      if (data.obsolete) this.packageObsolete = true;
      if (data.report_unavailable) {
        this.loading = false;
        this.stage = null;
        this.refreshDelay = 0;
        this.reportUnavailable = true;
        this.chart = null;
        this.incompatibleLicenses = [];
        this.missedFiles = [];
        this.unresolvedMatches = 0;
        this.matchingGlobs = [];
        this.emails = [];
        this.urls = [];
        this.risks = {};
        this.files = [];
        return;
      }

      if (data.error) {
        this.loading = true;
        this.stage = data.stage ?? null;
        this.refreshDelay = 5000;
        return;
      }

      this.loading = false;
      this.refreshDelay = 0;
      this.reportUnavailable = false;
      this.chart = data.chart;
      this.incompatibleLicenses = data.incompatible_licenses;
      this.missedFiles = data.missed_files;
      this.unresolvedMatches = data.package.unresolved_matches;
      if (data.package.name) this.packageName = data.package.name;
      this.matchingGlobs = data.matching_globs;
      this.emails = data.emails;
      this.urls = data.urls;

      const max = data.max_files_per_license;
      let counter = 0;
      const sortedRisks = Object.keys(data.risks).sort((a, b) => Number(b) - Number(a));
      for (const risk of sortedRisks) {
        for (const lic of data.risks[risk]) {
          counter += 1;
          lic.list_id = `filelist-${counter}`;
          lic.list_class = lic.files.length > 3 ? 'collapse' : 'collapse show';
          if (max && lic.files.length > max + 1) {
            lic.shown_files = lic.files.slice(0, max + 1);
            lic.more_files = lic.files.length - (max + 1);
          } else {
            lic.shown_files = lic.files;
            lic.more_files = 0;
          }
        }
      }
      this.risks = data.risks;

      const existing = new Map(this.files.map(f => [f.id, f]));
      this.files = data.files.map(f => {
        const prev = existing.get(f.id);
        return {
          ...f,
          expanded: prev ? prev.expanded : f.expand,
          source: prev ? prev.source : null
        };
      });

      this.$nextTick(() => {
        for (const file of this.files) {
          if (file.expanded && !file.source) this.fetchSource(file);
        }
        this.handleInitialHash();
      });
    },
    handleInitialHash() {
      if (this.hashHandled) return;
      const match = (window.location.hash || '').match(/^#file-(\d+)$/);
      if (!match) {
        this.hashHandled = true;
        return;
      }
      const file = this.files.find(f => String(f.id) === match[1]);
      if (!file) return;
      this.hashHandled = true;
      this.scrollToFile(file);
    },
    async scrollToFile(file) {
      if (!file.expanded) file.expanded = true;
      if (!file.source) await this.fetchSource(file);
      await this.$nextTick();
      const el =
        document.getElementById('file-details-' + file.id) || document.querySelector('[name="file-' + file.id + '"]');
      if (el) el.scrollIntoView({behavior: 'smooth', block: 'start'});
    },
    async scrollToAction(id) {
      const action = this.pendingActions.find(a => a.id === id);
      if (!action) return;
      const file = this.files.find(f => f.id === action.fileId);
      if (!file) return;
      if (!file.expanded) file.expanded = true;
      if (!file.source) await this.fetchSource(file);
      await this.$nextTick();
      const indicator = document.getElementById('pending-indicator-' + id);
      const fallback = document.getElementById('file-details-' + file.id);
      const target = indicator || fallback;
      if (target) target.scrollIntoView({behavior: 'smooth', block: 'center'});
    },
    licenseChartSliceLabel(entry) {
      return `${entry.name}: ${entry.percent}%`;
    },
    normalizeChartLicenseName(name) {
      return String(name).replace(/:\s*\d+\s+files?$/u, '');
    },
    showLicenseChartTooltip(entry, event) {
      const position = this.licenseChartTooltipPosition(event);
      this.licenseChartTooltip = {...position, name: entry.name, percent: entry.percent};
    },
    moveLicenseChartTooltip(event) {
      if (this.licenseChartTooltip === null) return;
      this.licenseChartTooltip = {...this.licenseChartTooltip, ...this.licenseChartTooltipPosition(event)};
    },
    hideLicenseChartTooltip() {
      this.licenseChartTooltip = null;
    },
    licenseChartTooltipPosition(event) {
      const chart = event.currentTarget.closest('.license-composition-chart');
      const rect = chart.getBoundingClientRect();
      const fallbackX = rect.width / 2;
      const fallbackY = rect.height / 2;
      const x = event.clientX ? event.clientX - rect.left : fallbackX;
      const y = event.clientY ? event.clientY - rect.top : fallbackY;
      return {
        x: Math.min(Math.max(x, 24), rect.width - 24),
        y: Math.min(Math.max(y, 24), rect.height - 24)
      };
    },
    toggleExpand(file) {
      file.expanded = !file.expanded;
      if (file.expanded && !file.source) this.fetchSource(file);
    },
    async fetchSource(file, start = 0, end = 0) {
      const qs = new URLSearchParams();
      if (start) qs.set('start', start);
      if (end) qs.set('end', end);
      const url = `/reviews/fetch_source/${file.id}.json${qs.toString() ? '?' + qs.toString() : ''}`;
      const res = await fetch(url);
      if (!res.ok) return;
      const data = await res.json();
      file.source = data.source;
    },
    onExtend(file, payload) {
      // Reset re-fetches with no start/end so source_for returns the report's
      // default view (original match boundaries + a few lines of context).
      if (payload.kind === 'reset') return this.fetchSource(file);

      let start = Number(payload.start);
      let end = Number(payload.end);
      switch (payload.kind) {
        case 'one-line-above':
          start -= 1;
          break;
        case 'one-line-below':
          end += 1;
          break;
        case 'top':
          start = 1;
          break;
        case 'bottom':
          end += 3000;
          break;
        case 'match-above':
          start = Number(payload.prevstart);
          break;
        case 'match-below':
          end = Number(payload.nextend);
          break;
      }
      this.fetchSource(file, start, end);
    },
    onFileLinkClick(id) {
      const file = this.files.find(f => String(f.id) === String(id));
      if (!file) return;
      return this.scrollToFile(file);
    },
    pendingActionsForFile(fileId) {
      return this.pendingActions.filter(a => a.fileId === fileId);
    },
    async openEditor(meta) {
      let snippetId = meta.snippetId;
      if (snippetId === null) {
        try {
          const data = await resolveSnippetFromFile(meta);
          snippetId = data.snippet;
        } catch (err) {
          // eslint-disable-next-line no-alert
          alert(err.message ?? String(err));
          return;
        }
      }
      await this.showInlineEditor({
        snippetId,
        fileId: meta.fileId,
        startLine: meta.startLine,
        endLine: meta.endLine,
        hash: meta.hash ?? null,
        from: meta.from ?? null,
        filePath: meta.filePath ?? null,
        initial: null,
        editingId: null
      });
    },
    async showInlineEditor(payload) {
      const file = this.files.find(f => f.id === payload.fileId);
      if (file) {
        if (!file.expanded) file.expanded = true;
        if (!file.source) await this.fetchSource(file);
      }
      this.openInlineEditor = {...payload, key: ++openEditorKeySeq};
      await this.$nextTick();
      const el = document.getElementById('inline-snippet-editor');
      if (el) el.scrollIntoView({block: 'nearest'});
    },
    closeInlineEditor() {
      this.openInlineEditor = null;
    },
    onEditorSubmit(payload) {
      const ctx = this.openInlineEditor ?? {};
      const editingId = ctx.editingId ?? null;
      const existingIdx = editingId !== null ? this.pendingActions.findIndex(a => a.id === editingId) : -1;
      const baseId = existingIdx >= 0 ? this.pendingActions[existingIdx].id : ++pendingActionIdSeq;
      const action = {
        id: baseId,
        snippetId: ctx.snippetId,
        fileId: ctx.fileId,
        startLine: ctx.startLine,
        endLine: ctx.endLine,
        hash: ctx.hash,
        from: ctx.from,
        action: payload.action,
        formData: payload.formData,
        license: payload.license || (payload.formData && payload.formData.license) || '',
        locationLabel: `${ctx.filePath ?? `file ${ctx.fileId}`}:${ctx.startLine}-${ctx.endLine}`,
        state: 'pending',
        error: null
      };
      if (existingIdx >= 0) {
        this.pendingActions.splice(existingIdx, 1, action);
      } else {
        this.pendingActions.push(action);
      }
      this.closeInlineEditor();
    },
    dismissAction(id) {
      const idx = this.pendingActions.findIndex(a => a.id === id);
      if (idx >= 0) this.pendingActions.splice(idx, 1);
    },
    suggestGlob(path) {
      // Pre-fill with the file path, but replace the versioned top-level directory's version with
      // "*" so the glob applies to future versions too (e.g. alloy-1.2.3/x/y.log -> alloy-*/x/y.log).
      const parts = String(path).split('/');
      parts[0] = parts[0].replace(/-[0-9][^/]*$/, '-*');
      return parts.join('/');
    },
    openGlobProposal(file) {
      this.globProposalFileId = file.id;
      this.globProposalEditingId = null;
      this.$refs.globProposalModal.open({glob: this.suggestGlob(file.path), reason: ''});
    },
    onGlobProposalSubmit({glob, reason}) {
      const editingIdx =
        this.globProposalEditingId !== null
          ? this.pendingActions.findIndex(a => a.id === this.globProposalEditingId)
          : -1;
      const baseId = editingIdx >= 0 ? this.pendingActions[editingIdx].id : ++pendingActionIdSeq;
      const action = {
        id: baseId,
        snippetId: null,
        fileId: this.globProposalFileId,
        startLine: null,
        endLine: null,
        hash: null,
        from: this.packageName,
        action: 'propose-glob',
        formData: {glob, reason, from: this.packageName, package: this.pkgId},
        license: '',
        locationLabel: glob,
        state: 'pending',
        error: null
      };
      if (editingIdx >= 0) {
        this.pendingActions.splice(editingIdx, 1, action);
      } else {
        this.pendingActions.push(action);
      }
      this.globProposalEditingId = null;
    },
    handleKeydown(event) {
      if (event.ctrlKey || event.metaKey || event.altKey) return;
      const t = event.target;
      if (t && (t.isContentEditable || t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT')) {
        return;
      }
      if (event.key === 'n') {
        if (this.missedFiles.length === 0) return;
        event.preventDefault();
        this.gotoMatch(1);
      } else if (event.key === 'p') {
        if (this.missedFiles.length === 0) return;
        event.preventDefault();
        this.gotoMatch(-1);
      } else if (event.key === '?' || (event.key === '/' && event.shiftKey)) {
        event.preventDefault();
        this.showShortcuts();
      }
    },
    gotoMatch(direction) {
      // Walk the DOM in document order. Each unresolved match start carries a
      // `match-start` class (added by FileSource.vue). This is more reliable
      // than a pre-computed target list: files load asynchronously past
      // max_expanded_files, the rendered source can drop snippet lines when
      // adjacent snippets overlap, and the missed-file sort order does not
      // match the order files appear on screen.
      const els = Array.from(document.querySelectorAll('.match-start'));
      if (els.length === 0) return;

      let currentIdx = -1;
      if (this.currentMatchId) {
        currentIdx = els.findIndex(el => el.id === this.currentMatchId);
      }
      if (currentIdx < 0) {
        // No remembered position (or it's gone from the DOM): fall back to the
        // last match-start that's at or above the viewport top. A small
        // positive threshold absorbs the in-flight position of a still-
        // animating smooth scroll.
        for (let i = 0; i < els.length; i++) {
          if (els[i].getBoundingClientRect().top < 5) currentIdx = i;
          else break;
        }
      }

      const idx = Math.max(0, Math.min(els.length - 1, currentIdx + direction));
      const target = els[idx];
      this.currentMatchId = target.id;
      target.scrollIntoView({behavior: 'smooth', block: 'start'});
    },
    showShortcuts() {
      const el = document.getElementById('shortcutsModal');
      if (!el) return;
      if (!this.shortcutsModal) this.shortcutsModal = Modal.getOrCreateInstance(el);
      this.shortcutsModal.show();
    },
    async editAction(id) {
      const action = this.pendingActions.find(a => a.id === id);
      if (!action) return;
      if (action.action === 'propose-glob') {
        this.globProposalFileId = action.fileId;
        this.globProposalEditingId = action.id;
        this.$refs.globProposalModal.open({glob: action.formData.glob, reason: action.formData.reason ?? ''});
        return;
      }
      await this.showInlineEditor({
        snippetId: action.snippetId,
        fileId: action.fileId,
        startLine: action.startLine,
        endLine: action.endLine,
        hash: action.hash,
        from: action.from,
        filePath: action.locationLabel.split(':')[0],
        initial: action.formData,
        editingId: action.id
      });
    },
    async submitAllActions() {
      const queue = this.pendingActions.filter(a => a.state !== 'done');
      if (queue.length === 0) return;

      for (const action of queue) {
        action.state = 'submitting';
        action.error = null;
      }

      const body = {
        actions: queue.map(a => ({
          kind: a.action,
          snippetId: a.snippetId,
          formData: a.formData
        }))
      };
      let res;
      let data;
      let results;
      try {
        ({res, data, results} = await submitSnippetDecisions(body.actions));
      } catch (err) {
        for (const action of queue) {
          action.state = 'error';
          action.error = err.message ?? String(err);
        }
        return;
      }

      if (res.isSuccess && data && data.ok) {
        // All actions committed - reload to show fresh report.
        window.location.reload();
        return;
      }

      // Partial or full failure - surface per-action errors. Nothing was
      // written if the failure was at the validation phase, so leave the
      // queue alone for the user to fix and resubmit.
      for (let i = 0; i < queue.length; i++) {
        const action = queue[i];
        const result = results[i];
        if (result && result.error) {
          action.state = 'error';
          action.error = result.error;
        } else if (result && result.ok) {
          // Validation passed but the batch as a whole was rejected; treat as
          // rolled-back and reset the state so the user can resubmit.
          action.state = 'pending';
          action.error = null;
        } else {
          action.state = 'error';
          action.error = (data && data.error) || `Request failed (HTTP ${res.statusCode})`;
        }
      }
    }
  }
};
</script>

<style>
.report-tabs {
  align-items: stretch;
  border-bottom: 1px solid #d0d7de;
  display: flex;
  gap: 4px;
  margin: 24px 0 16px;
}
.report-tab {
  align-items: center;
  background: transparent;
  border: 1px solid transparent;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: #57606a;
  cursor: pointer;
  display: inline-flex;
  font-size: 14px;
  font-weight: 500;
  gap: 8px;
  margin-bottom: -1px;
  padding: 10px 16px;
  transition:
    background-color 0.15s,
    color 0.15s;
}
.report-tab:hover:not(:disabled):not(.active) {
  background: #f3f5f7;
  color: #1f2328;
}
.report-tab.active {
  background: #ffffff;
  border-color: #d0d7de;
  color: #1f2328;
  font-weight: 600;
}
.report-tab-badge {
  background: #eaeef2;
  border-radius: 10px;
  color: #57606a;
  font-size: 11px;
  font-weight: 600;
  line-height: 1;
  padding: 3px 8px;
}
.report-tab.active .report-tab-badge {
  background: #ddf4ff;
  color: #0969da;
}
.report-tab-badge.report-tab-badge-lawyer {
  background: #fff8c5;
  color: #7d4e00;
}
.report-tab.active .report-tab-badge.report-tab-badge-lawyer {
  background: #fbeec0;
  color: #5c3a00;
}
.report-tab-content {
  display: block;
}
.report-tab-pane {
  display: none;
  min-width: 0;
}
.report-tab-pane.is-active {
  display: block;
}
.license-composition-card {
  border: 1px solid #d0d7de;
  border-radius: 6px;
  overflow: visible;
}
.license-composition-header {
  align-items: center;
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  border-radius: 6px 6px 0 0;
  display: flex;
  gap: 1rem;
  justify-content: space-between;
  padding: 0.75rem 1rem;
}
.license-composition-header h3 {
  font-size: 1rem;
  line-height: 1.3;
  margin: 0;
}
.license-composition-total {
  align-items: flex-end;
  background: #fff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  display: flex;
  gap: 0.35rem;
  padding: 0.25rem 0.5rem;
  white-space: nowrap;
}
.license-composition-total-value {
  color: #24292f;
  font-size: 1rem;
  font-weight: 700;
  line-height: 1.1;
}
.license-composition-total-label {
  color: #57606a;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.2;
}
.license-composition-body {
  align-items: center;
  background: #fff;
  border-radius: 0 0 6px 6px;
  display: grid;
  gap: 1.25rem;
  grid-template-columns: minmax(180px, 240px) minmax(0, 1fr);
  padding: 1rem;
}
.license-composition-chart {
  align-items: center;
  aspect-ratio: 1;
  display: flex;
  justify-content: center;
  justify-self: center;
  max-width: 240px;
  min-width: 180px;
  padding: 2rem;
  position: relative;
  width: 100%;
}
.license-composition-donut {
  filter: drop-shadow(0 1px 2px rgba(27, 31, 36, 0.08));
  inset: 0;
  overflow: visible;
  position: absolute;
  transform: rotate(-90deg);
}
.license-composition-donut-track,
.license-composition-slice {
  fill: none;
  stroke-width: 24;
}
.license-composition-donut-track {
  stroke: #eaeef2;
}
.license-composition-slice {
  cursor: help;
  transition:
    opacity 0.12s ease,
    stroke-width 0.12s ease;
}
.license-composition-slice:hover {
  opacity: 0.88;
  stroke-width: 26;
}
.license-composition-chart-label {
  align-items: center;
  background: #fff;
  border-radius: 50%;
  box-shadow: inset 0 0 0 1px rgba(27, 31, 36, 0.08);
  color: #24292f;
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  height: 50%;
  justify-content: center;
  line-height: 1.15;
  max-width: 50%;
  min-width: 0;
  position: relative;
  text-align: center;
  z-index: 1;
}
.license-composition-chart-label b {
  font-size: 1.8rem;
  letter-spacing: 0;
}
.license-composition-chart-label span {
  color: #57606a;
  font-size: 12px;
  font-weight: 600;
  max-width: 100%;
  overflow-wrap: anywhere;
}
.license-composition-tooltip {
  align-items: center;
  background: #24292f;
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(140, 149, 159, 0.2);
  color: #fff;
  display: flex;
  flex-direction: column;
  font-size: 12px;
  font-weight: 600;
  gap: 0.1rem;
  line-height: 1.35;
  overflow-wrap: anywhere;
  padding: 0.35rem 0.5rem;
  pointer-events: none;
  position: absolute;
  text-align: center;
  transform: translate(-50%, calc(-100% - 10px));
  width: 180px;
  z-index: 2;
}
.license-composition-tooltip b {
  font-size: 13px;
  letter-spacing: 0;
}
.license-composition-tooltip span {
  max-width: 100%;
}
.license-composition-list {
  display: grid;
  gap: 0.5rem;
  list-style: none;
  margin: 0;
  padding: 0;
}
.license-composition-item {
  display: grid;
  gap: 0.35rem;
}
.license-composition-item-header {
  align-items: center;
  display: grid;
  gap: 0.75rem;
  grid-template-columns: auto minmax(0, 1fr) auto;
}
.license-composition-swatch {
  border-radius: 50%;
  height: 10px;
  width: 10px;
}
.license-composition-name {
  color: #24292f;
  font-weight: 600;
  min-width: 0;
  overflow-wrap: anywhere;
}
.license-composition-percent {
  color: #24292f;
  font-size: 13px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  min-width: 3.5em;
  text-align: right;
}
.license-composition-meter {
  background: #eaeef2;
  border-radius: 999px;
  height: 8px;
  margin-left: 1.35rem;
  overflow: hidden;
}
.license-composition-meter span {
  border-radius: inherit;
  display: block;
  height: 100%;
  min-width: 3px;
}
.risk-license-section {
  margin: 1.75rem 0 1.75rem;
}
.risk-license-section-unresolved {
  margin-top: 0;
}
.risk-license-help-text {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 8px;
  color: #57606a;
  font-size: 13px;
  line-height: 1.45;
  margin: 1.5rem 0 1.1rem;
  padding: 0.7rem 0.85rem;
  position: relative;
}
.risk-license-help-text::before,
.risk-license-help-text::after {
  border-left: 8px solid transparent;
  border-right: 8px solid transparent;
  content: '';
  left: 1rem;
  position: absolute;
}
.risk-license-help-text::before {
  border-top: 8px solid #d0d7de;
  bottom: -8px;
}
.risk-license-help-text::after {
  border-top: 8px solid #f6f8fa;
  bottom: -7px;
}
.risk-license-heading {
  align-items: center;
  display: flex;
  gap: 0.75rem;
  line-height: 1;
  margin: 0 0 -1px;
  padding-left: 0;
  position: relative;
  z-index: 2;
}
.risk-license-heading .risk-license-summary {
  margin-left: auto;
}
.risk-license-heading > .badge {
  border: 1px solid transparent;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  box-shadow: none;
  font-size: 12px;
  letter-spacing: 0.01em;
  line-height: 1;
  padding: 0.45rem 0.7rem;
}
.risk-license-summary {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: #57606a;
  display: inline-block;
  font-size: 12px;
  font-weight: 500;
  line-height: 1;
  padding: 0.45rem 0.7rem;
  white-space: nowrap;
}
.risk-license-list {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 0 6px 6px 6px;
  list-style: none;
  margin: 0;
  overflow: hidden;
  padding: 0;
}
.risk-license-section-unresolved .risk-license-list {
  border-top-right-radius: 0;
}
.risk-license-item {
  background: #ffffff;
  border-top: 1px solid #d8dee4;
  padding: 0.5rem 1rem;
  position: relative;
  transition: background-color 0.15s ease;
}
.risk-license-item:first-child {
  border-top: 0;
}
.risk-license-item:hover {
  background: #f6f8fa;
}
.risk-license-row {
  align-items: center;
  display: grid;
  gap: 0.75rem;
  grid-template-columns: minmax(0, 1fr) auto;
}
.risk-license-name {
  color: #1f2328;
  font-weight: 600;
  line-height: 1.35;
  min-width: 0;
  overflow-wrap: anywhere;
}
.risk-license-count {
  align-items: center;
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 999px;
  color: #57606a;
  display: inline-flex;
  font-size: 12px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  justify-content: center;
  line-height: 1;
  min-width: 4.75rem;
  padding: 0.35rem 0.6rem;
  text-decoration: none;
  white-space: nowrap;
}
.risk-license-count:hover,
.risk-license-count:focus {
  background: #f0f6ff;
  border-color: #d0d7de;
  color: #0969da;
  text-decoration: none;
}
.risk-license-flags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  margin: 0.4rem 0 0;
}
.risk-license-flag {
  align-items: center;
  background: #fff8c5;
  border: 1px solid #f0d98b;
  border-radius: 999px;
  color: #5c4500;
  display: inline-flex;
  font-size: 12px;
  font-weight: 600;
  line-height: 1;
  padding: 0.3rem 0.55rem;
  white-space: nowrap;
}
.risk-file-list {
  border-left: 1px solid #d0d7de;
  color: #57606a;
  font-size: 13px;
  list-style: none;
  margin: 0.3rem 0 0.1rem 0.35rem;
  padding-left: 0.9rem;
}
.risk-file-list li {
  align-items: center;
  display: grid;
  gap: 0.55rem;
  grid-template-columns: auto minmax(0, 1fr);
  line-height: 1.35;
  position: relative;
}
.risk-file-list li::before {
  background: #6e7781;
  border: 2px solid #ffffff;
  border-radius: 50%;
  box-shadow: 0 0 0 1px #d0d7de;
  content: '';
  height: 0.45rem;
  margin-left: -1.15rem;
  width: 0.45rem;
}
.risk-file-list li + li {
  margin-top: 0.35rem;
}
.risk-file-list .file-link {
  color: #57606a;
  font-size: 13px;
  overflow-wrap: anywhere;
  text-decoration-color: transparent;
}
.risk-file-list .file-link:hover,
.risk-file-list .file-link:focus {
  color: #0550ae;
  text-decoration-color: currentColor;
}
.risk-unresolved-list {
  margin-bottom: 0;
}
.risk-unresolved-item {
  background: linear-gradient(90deg, rgba(191, 135, 0, 0.08), #ffffff 2.5rem);
  padding-bottom: 0.5rem;
  padding-top: 0.5rem;
}
.risk-unresolved-item:hover {
  background: linear-gradient(90deg, rgba(191, 135, 0, 0.12), #f6f8fa 2.5rem);
}
.risk-unresolved-row {
  align-items: center;
  display: grid;
  gap: 0.6rem;
  grid-template-columns: minmax(180px, 1.2fr) minmax(180px, 1fr) auto;
}
.risk-unresolved-file {
  color: #57606a;
  font-size: 13px;
  font-weight: 500;
  line-height: 1.35;
  min-width: 0;
  overflow-wrap: anywhere;
  text-decoration-color: transparent;
}
.risk-unresolved-file:hover,
.risk-unresolved-file:focus {
  color: #0550ae;
  text-decoration-color: currentColor;
}
.risk-unresolved-match {
  align-items: center;
  color: #57606a;
  display: inline-flex;
  font-size: 13px;
  gap: 0.35rem;
  min-width: 0;
  overflow-wrap: anywhere;
}
.risk-unresolved-match::before {
  background: #bf8700;
  border-radius: 999px;
  content: '';
  flex: 0 0 auto;
  height: 0.5rem;
  width: 0.5rem;
}
.risk-unresolved-estimate {
  align-items: center;
  color: #57606a;
  display: inline-flex;
  font-size: 12px;
  gap: 0.45rem;
  justify-self: end;
  white-space: nowrap;
}
.report-artifact-section {
  margin: 1.75rem 0;
}
.report-artifact-heading {
  align-items: center;
  display: flex;
  line-height: 1;
  margin: 0 0 -1px;
  position: relative;
  z-index: 2;
}
.report-artifact-label {
  align-items: center;
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: #57606a;
  display: inline-flex;
  font-size: 12px;
  font-weight: 600;
  gap: 0.45rem;
  letter-spacing: 0.01em;
  line-height: 1;
  padding: 0.45rem 0.7rem;
  text-decoration: none;
}
.report-artifact-label:hover,
.report-artifact-label:focus {
  background: #ffffff;
  color: #1f2328;
  text-decoration: none;
}
.report-artifact-label.collapsed {
  border-bottom: 1px solid #d0d7de;
  border-radius: 6px;
}
.report-artifact-label.collapsed:hover,
.report-artifact-label.collapsed:focus {
  background: #f6f8fa;
}
.report-artifact-label-static {
  cursor: default;
}
.report-artifact-label-static:hover,
.report-artifact-label-static:focus {
  background: #f6f8fa;
  color: #57606a;
}
.report-artifact-list {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 0 6px 6px 6px;
  list-style: none;
  margin: 0;
  overflow: hidden;
  padding: 0;
}
.report-artifact-item {
  align-items: center;
  background: #ffffff;
  border-top: 1px solid #d8dee4;
  display: grid;
  gap: 0.75rem;
  grid-template-columns: minmax(0, 1fr) minmax(160px, 0.45fr);
  padding: 0.65rem 1rem;
  transition: background-color 0.15s ease;
}
.report-artifact-item:first-child {
  border-top: 0;
}
.report-artifact-item:hover {
  background: #f6f8fa;
}
.report-artifact-value {
  color: #57606a;
  font-size: 13px;
  font-weight: 500;
  line-height: 1.35;
  min-width: 0;
  overflow-wrap: anywhere;
}
.report-artifact-source {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 999px;
  color: #57606a;
  font-size: 12px;
  font-weight: 600;
  justify-self: end;
  line-height: 1;
  max-width: 100%;
  overflow-wrap: anywhere;
  padding: 0.35rem 0.6rem;
  text-align: right;
}
.report-glob-list {
  border-radius: 0 6px 6px 6px;
}
.report-glob-item {
  display: block;
  padding: 0.55rem 1rem;
}
.report-glob-pattern {
  background: transparent;
  color: #57606a;
  font-size: 13px;
  overflow-wrap: anywhere;
  padding: 0;
}
.file-actions {
  align-items: center;
  display: inline-flex;
  gap: 0.75rem;
}
.file-action-link {
  color: #57606a;
  text-decoration: none;
}
.file-action-link:hover,
.file-action-link:focus {
  color: #0969da;
}
@media (max-width: 700px) {
  .license-composition-body {
    grid-template-columns: 1fr;
  }
  .license-composition-chart {
    max-width: 220px;
  }
  .risk-license-heading {
    flex-wrap: wrap;
    margin-bottom: -1px;
  }
  .risk-license-summary {
    line-height: 1.3;
    white-space: normal;
  }
  .risk-license-row {
    align-items: flex-start;
    grid-template-columns: 1fr;
  }
  .risk-license-count {
    justify-self: start;
  }
  .risk-unresolved-row {
    align-items: flex-start;
    grid-template-columns: 1fr;
  }
  .risk-unresolved-estimate {
    justify-self: start;
  }
  .report-artifact-item {
    align-items: flex-start;
    grid-template-columns: 1fr;
  }
  .report-artifact-source {
    justify-self: start;
    text-align: left;
  }
}
.shortcuts-modal-body {
  padding: 1rem 1.25rem 1.25rem;
}
.shortcuts-section-title {
  font-size: 0.75rem;
  font-weight: 600;
  margin: 0 0 0.5rem;
  color: #57606a;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.shortcuts-list {
  margin: 0;
}
.shortcuts-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.5rem 0;
  border-bottom: 1px solid #eaeef2;
}
.shortcuts-row:last-child {
  border-bottom: none;
}
.shortcuts-row dt {
  font-weight: 400;
}
.shortcuts-row dd {
  margin: 0;
}
.shortcuts-row kbd {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  box-shadow: inset 0 -1px 0 #d0d7de;
  color: #1f2328;
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', monospace;
  font-size: 0.75rem;
  padding: 3px 6px;
  min-width: 1.5em;
  text-align: center;
  display: inline-block;
}
</style>
