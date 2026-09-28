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
      <button
        type="button"
        class="report-tab"
        :class="{active: activeTab === 'artifacts'}"
        role="tab"
        :aria-selected="activeTab === 'artifacts'"
        data-tab="artifacts"
        @click="setActiveTab('artifacts')"
      >
        <i class="fa-solid fa-fingerprint"></i>
        Artifacts
      </button>
      <!-- Last because it is the only optional tab, so the others keep their position and number key -->
      <button
        v-if="components.length > 0"
        type="button"
        class="report-tab"
        :class="{active: activeTab === 'components'}"
        role="tab"
        :aria-selected="activeTab === 'components'"
        data-tab="components"
        @click="setActiveTab('components')"
      >
        <i class="fa-solid fa-cubes"></i>
        Components
        <span class="report-tab-badge" data-component-count>{{ components.length }}</span>
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
              <LegalLoading message="Preparing the report, this may take a moment..." />
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
          <CavilNoticePanel
            v-if="reindexing"
            title="Report update in progress"
            tone="info"
            icon="fa-solid fa-arrows-rotate"
            data-reindexing-notice
          >
            <p class="cavil-notice-summary">
              You are reading the previous report, frozen until the new one replaces it.
            </p>
            <div v-if="rebuildStage" class="reindexing-progress">
              <ProgressBar :stage="rebuildStage" :labels="rebuildLabels" compact />
            </div>
          </CavilNoticePanel>
          <LicenseCompositionChart
            id="license-chart"
            :entries="licenseChartEntries"
            title="License composition"
            singular-label="file"
            plural-label="files"
          />

          <LicenseCompatibilityMatrix
            v-if="licenseCompatibility.licenses.length > 0"
            :licenses="licenseCompatibility.licenses"
            :matrix="licenseCompatibility.matrix"
            :proximity="licenseCompatibility.proximity"
            :pkg-id="pkgId"
          />

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
                    <span class="risk-unresolved-name">
                      <a
                        :href="'#file-' + file.id"
                        class="file-link risk-unresolved-file"
                        :aria-expanded="isOpen(unresolvedTarget(file)) ? 'true' : 'false'"
                        @click.prevent="togglePanel(unresolvedTarget(file))"
                        ><i class="fa-solid file-link-chevron" aria-hidden="true"></i><FilePath :path="file.name"
                      /></a>
                      <span v-if="file.new" class="risk-new">new</span>
                    </span>
                    <span class="risk-unresolved-match">
                      <b>{{ file.match }}%</b> similarity to <b v-html="file.license_html"></b>
                    </span>
                    <span class="risk-unresolved-estimate">
                      <span>estimated</span>
                      <span :class="['badge', 'estimated-risk', estimatedRiskClass(file.max_risk)]">
                        Risk {{ file.max_risk }}
                      </span>
                    </span>
                    <ReportFileActions
                      v-if="isOpen(unresolvedTarget(file))"
                      :file-id="panel.fileId"
                      :view-url="panelViewUrl"
                      :has-admin-role="hasAdminRole"
                      :has-contributor-role="hasContributorRole"
                      @glob="openGlobProposal(panel, $event)"
                      @close="panel = null"
                    />
                  </div>
                  <Transition name="cavil-reveal">
                    <ReportMatchPanel
                      v-if="isOpen(unresolvedTarget(file))"
                      :panel="panel"
                      :pkg-id="pkgId"
                      :step="panelStep"
                      :has-admin-role="hasAdminRole"
                      :has-contributor-role="hasContributorRole"
                      :read-only="reindexing"
                      :pending-actions="pendingActionsForFile(panel.fileId)"
                      :inline-editor="
                        openInlineEditor && openInlineEditor.fileId === panel.fileId ? openInlineEditor : null
                      "
                      @show-more="showMore"
                      @extend="onExtend"
                      @open-editor="openEditor"
                      @ignore-match="onIgnoreMatch"
                      @dismiss-action="dismissAction"
                      @close-editor="closeInlineEditor"
                      @editor-submit="onEditorSubmit"
                    />
                  </Transition>
                </li>
              </ul>
            </div>
          </div>

          <div v-for="risk in sortedRisks" :key="risk" class="risk-license-section">
            <h4 class="risk-license-heading">
              <div :class="['badge', riskBadgeClass(risk)]">Risk {{ risk }}</div>
            </h4>
            <ul :id="'risk-' + risk" class="risk-license-list">
              <li
                v-for="lic in risks[risk]"
                :key="lic.key"
                class="risk-license-item"
                :class="{'is-catch-all': lic.catch_all}"
              >
                <div class="risk-license-row">
                  <span class="risk-license-label">
                    <span class="risk-license-name" v-html="lic.name_html"></span>
                    <span v-if="lic.new" class="risk-new">new</span>
                    <span v-if="lic.scope" class="risk-license-scope">only in {{ scopeLabel(lic.scope) }}</span>
                  </span>
                  <button
                    v-if="lic.classification && lic.classification.length > 0"
                    type="button"
                    class="license-obligations-toggle"
                    :aria-expanded="openObligations.has(lic.key) ? 'true' : 'false'"
                    @click="toggleObligations(lic.key)"
                  >
                    <i
                      :class="['fa-solid', openObligations.has(lic.key) ? 'fa-caret-down' : 'fa-caret-right']"
                      aria-hidden="true"
                    ></i>
                    {{ obligationsLabel(lic.classification) }}
                  </button>
                  <span class="risk-license-count">
                    {{ lic.files.length }} {{ lic.files.length === 1 ? 'file' : 'files' }}
                  </span>
                </div>
                <div v-if="lic.flags.length > 0" class="risk-license-flags" aria-label="License flags">
                  <span v-for="flag in lic.flags" :key="flag" class="risk-license-flag">
                    {{ licenseFlagLabel(flag) }}
                  </span>
                </div>
                <Transition name="cavil-reveal">
                  <LicenseObligations
                    v-if="openObligations.has(lic.key)"
                    :entries="lic.classification"
                    :label="lic.spdx || lic.name"
                  />
                </Transition>
                <div class="risk-files">
                  <ul class="risk-file-list">
                    <li v-for="file in shownFiles(lic)" :key="file[0]">
                      <a
                        :href="'#file-' + file[0]"
                        class="file-link"
                        :aria-expanded="isOpen(licenseTarget(risk, lic, file)) ? 'true' : 'false'"
                        @click.prevent="togglePanel(licenseTarget(risk, lic, file))"
                        ><i class="fa-solid file-link-chevron" aria-hidden="true"></i><FilePath :path="file[1]"
                      /></a>
                      <ReportFileActions
                        v-if="isOpen(licenseTarget(risk, lic, file))"
                        :file-id="panel.fileId"
                        :view-url="panelViewUrl"
                        :has-admin-role="hasAdminRole"
                        :has-contributor-role="hasContributorRole"
                        @glob="openGlobProposal(panel, $event)"
                        @close="panel = null"
                      />
                      <Transition name="cavil-reveal">
                        <ReportMatchPanel
                          v-if="isOpen(licenseTarget(risk, lic, file))"
                          :panel="panel"
                          :pkg-id="pkgId"
                          :step="panelStep"
                          :has-admin-role="hasAdminRole"
                          :has-contributor-role="hasContributorRole"
                          :read-only="reindexing"
                          :pending-actions="pendingActionsForFile(panel.fileId)"
                          :inline-editor="
                            openInlineEditor && openInlineEditor.fileId === panel.fileId ? openInlineEditor : null
                          "
                          @show-more="showMore"
                          @extend="onExtend"
                          @open-editor="openEditor"
                          @ignore-match="onIgnoreMatch"
                          @dismiss-action="dismissAction"
                          @close-editor="closeInlineEditor"
                          @editor-submit="onEditorSubmit"
                        />
                      </Transition>
                    </li>
                    <li v-if="lic.files.length - shownFiles(lic).length > 0">
                      <button
                        v-if="!openLists.has(lic.key)"
                        type="button"
                        class="risk-file-more"
                        @click="openLists.add(lic.key)"
                      >
                        {{ lic.files.length - shownFiles(lic).length }} more
                      </button>
                      <span v-else class="risk-file-more">{{ lic.files.length - shownFiles(lic).length }} more</span>
                    </li>
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

          <br />
        </div>
        <PendingActionsWidget v-if="isAdminOrContributor && pendingActions.length > 0" :read-only="reindexing" />
        <GlobProposalModal ref="globProposalModal" @submit="onGlobProposalSubmit" />
      </div>
      <div
        v-if="components.length > 0"
        class="report-tab-pane"
        :class="{'is-active': activeTab === 'components'}"
        :aria-hidden="activeTab !== 'components'"
        id="report-components-pane"
        role="tabpanel"
      >
        <LicenseCompositionChart
          id="component-license-chart"
          :entries="componentLicenseChartEntries"
          :limit="componentLicenseChartLimit"
          title="Component license composition"
          singular-label="component"
          plural-label="components"
        />

        <section class="cavil-list-toolbar report-component-toolbar" aria-label="Component filters">
          <form class="cavil-list-filter report-component-filter" @submit.prevent>
            <label for="report-component-filter-input">Filter components</label>
            <div class="cavil-list-filter-box">
              <i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>
              <input
                id="report-component-filter-input"
                v-model="componentFilter"
                type="search"
                class="form-control"
                placeholder="Filter components by name, type, or license"
                autocomplete="off"
                autocapitalize="none"
                spellcheck="false"
              />
            </div>
          </form>
        </section>

        <p v-if="filteredComponents.length === 0" class="report-component-empty">No components match this filter.</p>
        <ul v-else class="report-artifact-list report-component-list">
          <li
            v-for="component in filteredComponents"
            :key="component.purl"
            class="report-artifact-item report-component-item"
          >
            <a
              v-if="component.file_url"
              :href="component.file_url"
              target="_blank"
              rel="noopener noreferrer"
              class="report-component-name"
              title="Open component file in a new tab"
            >
              {{ component.name
              }}<span v-if="component.version" class="report-component-version">@{{ component.version }}</span>
            </a>
            <span v-else class="report-component-name">
              {{ component.name
              }}<span v-if="component.version" class="report-component-version">@{{ component.version }}</span>
            </span>
            <span v-if="component.license_html" class="report-component-license" v-html="component.license_html"></span>
            <span v-else class="report-component-license"></span>
            <span class="report-component-ecosystem">{{ component.type }}</span>
            <a
              v-if="component.search_url"
              :href="component.search_url"
              target="_blank"
              rel="noopener noreferrer"
              class="report-component-search"
              title="Find other packages that ship this component"
              aria-label="Find other packages that ship this component"
              ><i class="fa-solid fa-magnifying-glass"></i
            ></a>
            <span v-else></span>
          </li>
        </ul>
        <br />
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
          @ready="onNotesReady"
        />
      </div>
      <div
        class="report-tab-pane"
        :class="{'is-active': activeTab === 'artifacts'}"
        :aria-hidden="activeTab !== 'artifacts'"
        id="report-artifacts-pane"
        role="tabpanel"
      >
        <ReportArtifacts v-if="artifactsMounted" :pkg-id="pkgId" />
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
                <dt>Jump to Risk 9 unresolved matches list</dt>
                <dd><kbd>u</kbd></dd>
              </div>
              <div v-if="licenseCompatibility.licenses.length > 0" class="shortcuts-row">
                <dt>Jump to license compatibility</dt>
                <dd><kbd>c</kbd></dd>
              </div>
              <div class="shortcuts-row">
                <dt>Scroll to top of report</dt>
                <dd><kbd>t</kbd></dd>
              </div>
              <div class="shortcuts-row">
                <dt>Jump to review finalization</dt>
                <dd><kbd>f</kbd></dd>
              </div>
              <div class="shortcuts-row">
                <dt>Open Report tab</dt>
                <dd><kbd>1</kbd></dd>
              </div>
              <div class="shortcuts-row">
                <dt>Open Notes tab</dt>
                <dd><kbd>2</kbd></dd>
              </div>
              <div class="shortcuts-row">
                <dt>Open Artifacts tab</dt>
                <dd><kbd>3</kbd></dd>
              </div>
              <div class="shortcuts-row">
                <dt>Open Components tab</dt>
                <dd><kbd>4</kbd></dd>
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
import CavilNoticePanel from './CavilNoticePanel.vue';
import FilePath from './FilePath.vue';
import GlobProposalModal from './GlobProposalModal.vue';
import LegalLoading from './LegalLoading.vue';
import LicenseCompatibilityMatrix from './LicenseCompatibilityMatrix.vue';
import LicenseCompositionChart from './LicenseCompositionChart.vue';
import LicenseObligations, {obligationsLabel} from './LicenseObligations.vue';
import PendingActionsWidget from './PendingActionsWidget.vue';
import ProgressBar from './ProgressBar.vue';
import ReportArtifacts from './ReportArtifacts.vue';
import ReportFileActions from './ReportFileActions.vue';
import ReportMatchPanel from './ReportMatchPanel.vue';
import ReportNotes from './ReportNotes.vue';
import {fileViewUrl} from '../helpers/links.js';
import {
  ignorePendingAction,
  resolveMatchChecksum,
  resolveSnippetFromFile,
  submitSnippetDecisions
} from '../helpers/snippetDecisions.js';
import Refresh from '../mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import {Modal} from 'bootstrap';

let pendingActionIdSeq = 0;
let openEditorKeySeq = 0;
const COMPONENT_LICENSE_CHART_LIMIT = 7;

// The stages a rebuild of an existing report goes through, matching Cavil::Plugin::Helpers. A reindex that
// reuses the sources it already has skips "Unpacking" and the bar simply advances past it.
const REBUILD_LABELS = ['Queued', 'Unpacking', 'Indexing', 'Analyzing'];
const STATE_POLL_DELAY = 5000;
const IDLE_POLL_DELAY = 15000;
const FOLDED_FILES = 3;
const PANEL_STEP = 10;

export default {
  name: 'ReportDetails',
  components: {
    CavilNoticePanel,
    FilePath,
    GlobProposalModal,
    LegalLoading,
    LicenseCompatibilityMatrix,
    LicenseCompositionChart,
    LicenseObligations,
    PendingActionsWidget,
    ProgressBar,
    ReportArtifacts,
    ReportFileActions,
    ReportMatchPanel,
    ReportNotes
  },
  mixins: [Refresh],
  emits: ['rebuild-finished'],
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
      componentFilter: '',
      components: [],
      licenseCompatibility: {licenses: [], matrix: {}, proximity: {}},
      loading: true,
      matchingGlobs: [],
      maxFiles: Infinity,
      missedFiles: [],
      openLists: new Set(),
      openObligations: new Set(),
      openInlineEditor: null,
      packageName: '',
      panel: null,
      panelStep: PANEL_STEP,
      globProposalFileId: null,
      globProposalEditingId: null,
      globProposalCreate: false,
      pendingActions: [],
      hashHandled: false,
      activeTab: 'review',
      artifactsMounted: false,
      notesMounted: false,
      noteTotal: null,
      noteLawyerCount: 0,
      canPostLawyerOnly: false,
      packageObsolete: !!this.isObsolete,
      reportUnavailable: false,
      reindexing: false,
      rebuildStage: null,
      rebuildLabels: REBUILD_LABELS,
      reportChecksum: null,
      statePollTimer: null,
      seekNoteId: null,
      pendingNotesScroll: false,
      notesLoaded: false,
      metadataLoaded: false,
      refreshDelay: 5000,
      refreshUrl: `/reviews/report_details/${this.pkgId}`,
      risks: {},
      stage: null,
      unresolvedMatches: 0,
      currentMatchId: null,
      shortcutsModal: null
    };
  },
  computed: {
    licenseChartEntries() {
      if (this.chart === null) return [];

      const licenses = this.chart.licenses ?? [];
      const licensesHtml = this.chart.licenses_html ?? [];
      const files = (this.chart['num-files'] ?? []).map(value => Number(value));
      return licenses.map((name, index) => {
        const cleanName = this.normalizeChartLicenseName(name);
        return {name: cleanName, name_html: licensesHtml[index] ?? cleanName, count: files[index]};
      });
    },
    componentLicenseChartEntries() {
      const grouped = new Map();
      for (const component of this.components) {
        const name = String(component.license || '').trim() || 'No license detected';
        const current = grouped.get(name) || {name, name_html: component.license_html || name, count: 0};
        current.count += 1;
        grouped.set(name, current);
      }
      return Array.from(grouped.values());
    },
    componentLicenseChartLimit() {
      return COMPONENT_LICENSE_CHART_LIMIT;
    },
    filteredComponents() {
      const terms = this.componentFilter.toLowerCase().split(/\s+/u).filter(Boolean);
      if (terms.length === 0) return this.components;

      return this.components.filter(component => {
        const haystack = [component.name, component.version, component.type, component.license]
          .filter(Boolean)
          .join(' ')
          .toLowerCase();
        return terms.every(term => haystack.includes(term));
      });
    },
    panelViewUrl() {
      const first = this.panel?.source?.lines.find(line => line[1].end);
      return fileViewUrl(this.pkgId, this.panel.path, first ? first[0] : 0);
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
    if (this.statePollTimer !== null) {
      clearTimeout(this.statePollTimer);
      this.statePollTimer = null;
    }
    if (this.shortcutsModal) {
      this.shortcutsModal.dispose();
      this.shortcutsModal = null;
    }
  },
  methods: {
    setActiveTab(tab, {scrollIntoView = false} = {}) {
      this.activeTab = tab;
      if (tab === 'notes') this.notesMounted = true;
      if (tab === 'artifacts') this.artifactsMounted = true;
      if (scrollIntoView) this.$nextTick(this.scrollToTabs);
    },
    scrollToTabs() {
      const el = document.getElementById('report-tabs');
      if (el) el.scrollIntoView({behavior: 'smooth', block: 'start'});
    },
    applyInitialNoteHash() {
      // Permalink formats: #note-<id> for one note, #notes for the tab (where the listing note
      // icons link). Switch on mount so the deep link resolves before the user has to click.
      const hash = window.location.hash || '';
      const m = hash.match(/^#note-(\d+)$/);
      if (!m && hash !== '#notes') return;
      if (m) this.seekNoteId = Number(m[1]);
      // #note-<id> scrolls itself once ReportNotes has the note; #notes has nothing to seek, so it
      // waits for scrollToNotesWhenReady instead.
      else this.pendingNotesScroll = true;
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
    onMetadataLoaded() {
      this.metadataLoaded = true;
      this.scrollToNotesWhenReady();
    },
    onNotesReady() {
      this.notesLoaded = true;
      this.scrollToNotesWhenReady();
    },

    // Both halves have to be in place before a #notes deep link can scroll: the metadata above the
    // tab strip decides where it lands, and the notes below it make the page long enough to get
    // there at all. Either one arriving late leaves the reviewer looking at the top of the report.
    scrollToNotesWhenReady() {
      if (!this.pendingNotesScroll || !this.notesLoaded || !this.metadataLoaded) return;
      this.pendingNotesScroll = false;
      this.$nextTick(this.scrollToTabs);
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
    // States where the files are, never what to do about them: the path classifier is a heuristic, and a
    // marker that read as "ignore this" would hide a real license when it got one wrong.
    scopeLabel(scope) {
      const kinds = scope.map(kind => (kind === 'vendored' ? 'vendored' : `${kind}`));
      if (kinds.length === 1) return `${kinds[0]} files`;
      return `${kinds.slice(0, -1).join(', ')} and ${kinds[kinds.length - 1]} files`;
    },
    riskBadgeClass(risk) {
      const r = Number(risk);
      if (r === 9) return 'cavil-risk-unknown-badge';
      if (r <= 4) return 'text-bg-success';
      if (r === 5) return 'text-bg-warning';
      return 'text-bg-danger';
    },
    refreshData(data) {
      if (data.obsolete) this.packageObsolete = true;
      if (data.report_unavailable) {
        this.loading = false;
        this.stage = null;
        this.refreshDelay = 0;
        this.reportUnavailable = true;
        this.reindexing = false;
        this.rebuildStage = null;
        this.chart = null;
        this.licenseCompatibility = {licenses: [], matrix: {}, proximity: {}};
        this.missedFiles = [];
        this.unresolvedMatches = 0;
        this.matchingGlobs = [];
        this.components = [];
        this.risks = {};
        this.panel = null;
        return;
      }

      if (data.error) {
        this.loading = true;
        this.stage = data.stage ?? null;
        this.refreshDelay = 5000;
        this.reindexing = false;
        this.rebuildStage = null;
        return;
      }

      this.loading = false;
      this.reportUnavailable = false;

      // The report itself is not refetched on a timer anymore. From here on the cheap state poll watches
      // for a rebuild - one that is running now, or one somebody else starts later - and asks for the
      // whole report again only when there is a new one to show.
      this.refreshDelay = 0;
      this.reindexing = !!data.reindexing;
      this.rebuildStage = data.rebuild_stage ?? null;
      this.reportChecksum = data.checksum ?? null;
      this.scheduleStatePoll();

      this.chart = data.chart;
      this.licenseCompatibility = data.license_compatibility ?? {licenses: [], matrix: {}, proximity: {}};
      this.missedFiles = data.missed_files;
      this.unresolvedMatches = data.package.unresolved_matches;
      if (data.package.name) this.packageName = data.package.name;
      this.matchingGlobs = data.matching_globs;
      this.components = data.components;
      if (this.components.length === 0 && this.activeTab === 'components') this.activeTab = 'review';

      const max = data.max_files_per_license;
      this.maxFiles = max ? max + 1 : Infinity;
      for (const [risk, licenses] of Object.entries(data.risks)) {
        for (const lic of licenses) lic.key = `${risk}:${lic.name}`;
      }
      this.risks = data.risks;

      // An open panel is remembered by what it shows, not by file id: a reindex deletes and recreates every
      // matched_files row, so after a swap the ids are all new while the paths are the same
      if (this.panel) {
        const target = this.findTarget(this.panel);
        if (!target) this.panel = null;
        else if (target.fileId !== this.panel.fileId) this.openPanel(target, this.panel.groups);
      }
      this.$nextTick(this.handleInitialHash);
    },
    scheduleStatePoll() {
      if (this.statePollTimer !== null) return;
      this.statePollTimer = setTimeout(this.pollReportState, this.reindexing ? STATE_POLL_DELAY : IDLE_POLL_DELAY);
    },

    // Called when the reviewer starts a rebuild from the Reindex button. The report goes read-only
    // immediately instead of at the end of the slow idle tick, which may be a quarter minute away.
    watchRebuild() {
      this.reindexing = true;
      if (this.rebuildStage === null) this.rebuildStage = 1;
      if (this.statePollTimer !== null) {
        clearTimeout(this.statePollTimer);
        this.statePollTimer = null;
      }
      this.scheduleStatePoll();
    },

    // A rebuild is usually started by somebody else - a license pattern created against a completely
    // different package - so a settled report keeps a slow watch too, and the reviewer sees the notice
    // appear instead of finding out when a batch is refused. Watching costs one small request per tick
    // rather than assembling the whole report again, and the full report is refetched exactly once: when
    // the rebuild is over, or a new one has been promoted in its place.
    async pollReportState() {
      this.statePollTimer = null;

      let data;
      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.get(`/reviews/report_state/${this.pkgId}`);
        data = await res.json();
      } catch (err) {
        // Nothing on screen is wrong, the server just did not answer; try again on the next tick.
        this.scheduleStatePoll();
        return;
      }

      const promoted = data.checksum && this.reportChecksum && data.checksum !== this.reportChecksum;
      if (promoted || (this.reindexing && !data.reindexing)) {
        // The metadata is told separately, because the Reindex button it owns stops having anything to
        // offer at exactly this moment, and its own refresh may be most of a minute away.
        this.$emit('rebuild-finished');
        await this.doApiRefresh();
        return;
      }

      this.reindexing = !!data.reindexing;
      this.rebuildStage = data.rebuild_stage ?? null;
      this.scheduleStatePoll();
    },
    handleInitialHash() {
      if (this.hashHandled) return;
      this.hashHandled = true;
      const match = (window.location.hash || '').match(/^#file-(\d+)$/);
      if (!match) return;
      const target = this.targetForFile(Number(match[1]));
      if (target) this.revealPanel(target);
    },
    // The row a bare file id stands for: its unresolved snippets when it has any, else its first license
    targetForFile(id) {
      const missed = this.missedFiles.find(f => f.id === id);
      if (missed) return this.unresolvedTarget(missed);
      for (const risk of this.sortedRisks) {
        for (const lic of this.risks[risk]) {
          const file = lic.files.find(f => f[0] === id);
          if (file) return this.licenseTarget(risk, lic, file);
        }
      }
      return null;
    },
    unresolvedTarget(file) {
      return {list: 'unresolved', risk: 9, license: null, fileId: file.id, path: file.name};
    },
    licenseTarget(risk, lic, file) {
      return {list: 'license', risk: Number(risk), license: lic.name, fileId: file[0], path: file[1]};
    },
    panelKey(target) {
      return [target.list, target.risk, target.license, target.path].join(':');
    },
    isOpen(target) {
      return this.panel !== null && this.panel.key === this.panelKey(target);
    },
    // The same row in a freshly loaded report, or null when it is gone
    findTarget(target) {
      if (target.list === 'unresolved') {
        const file = this.missedFiles.find(f => f.name === target.path);
        return file ? this.unresolvedTarget(file) : null;
      }
      const lic = (this.risks[target.risk] ?? []).find(l => l.name === target.license);
      const file = lic ? lic.files.find(f => f[1] === target.path) : null;
      return file ? this.licenseTarget(target.risk, lic, file) : null;
    },
    obligationsLabel,
    toggleObligations(key) {
      if (!this.openObligations.delete(key)) this.openObligations.add(key);
    },
    shownFiles(lic) {
      return lic.files.slice(0, this.openLists.has(lic.key) ? this.maxFiles : FOLDED_FILES);
    },
    togglePanel(target) {
      if (this.isOpen(target)) this.panel = null;
      else this.openPanel(target);
    },
    // One panel at a time keeps memory bounded, and FileSource's element ids unique for a file listed twice
    openPanel(target, groups = PANEL_STEP) {
      this.panel = {...target, key: this.panelKey(target), groups, source: null, unavailable: false};
      return this.fetchPanel();
    },
    async revealPanel(target) {
      if (target.list === 'license') {
        const lic = this.risks[target.risk].find(l => l.name === target.license);
        if (!this.shownFiles(lic).some(f => f[0] === target.fileId)) this.openLists.add(lic.key);
      }
      if (!this.isOpen(target)) await this.openPanel(target);
      await this.$nextTick();
      document.getElementById('file-details-' + target.fileId)?.scrollIntoView({behavior: 'smooth', block: 'center'});
    },
    async fetchPanel(start = 0, end = 0) {
      const panel = this.panel;
      const query = {groups: panel.groups};
      if (panel.list === 'unresolved') query.unresolved = 1;
      else Object.assign(query, {license: panel.license, risk: panel.risk});
      if (start) query.start = start;
      if (end) query.end = end;
      const res = await fetch(`/reviews/fetch_source/${panel.fileId}.json?${new URLSearchParams(query)}`);
      if (!res.ok || this.panel !== panel) return;
      const {source} = await res.json();
      if (this.panel !== panel) return;

      // A re-unpack has the checkout torn down, so there is no source to show. Say that instead of
      // rendering an empty file, and leave any matches already on screen alone.
      if (source.unavailable) panel.unavailable = true;
      else Object.assign(panel, {source, unavailable: false});
    },
    // ponytail: refetches the larger page and drops manual extends, merge the new lines in if reviewers mind
    showMore() {
      this.panel.groups += PANEL_STEP;
      return this.fetchPanel();
    },
    scrollToUnresolvedList() {
      const el = document.getElementById('unmatched-files') || document.getElementById('filelist-snippets');
      if (el) el.scrollIntoView({behavior: 'smooth', block: 'start'});
    },
    async scrollToAction(id) {
      const action = this.pendingActions.find(a => a.id === id);
      if (!action) return;
      if (this.panel?.fileId !== action.fileId) {
        const target = this.targetForFile(action.fileId);
        if (!target) return;
        await this.revealPanel(target);
      }
      await this.$nextTick();
      const target =
        document.getElementById('pending-indicator-' + id) || document.getElementById('file-details-' + action.fileId);
      if (target) target.scrollIntoView({behavior: 'smooth', block: 'center'});
    },
    normalizeChartLicenseName(name) {
      return String(name).replace(/:\s*\d+\s+files?$/u, '');
    },
    onExtend(payload) {
      // Reset re-fetches with no start/end so source_for returns the panel's
      // default view (original match boundaries + a few lines of context).
      if (payload.kind === 'reset') return this.fetchPanel();

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
      this.fetchPanel(start, end);
    },
    scrollToCompatibility() {
      const el = document.getElementById('license-compatibility');
      if (el) el.scrollIntoView({behavior: 'smooth', block: 'start'});
    },
    pendingActionsForFile(fileId) {
      return this.pendingActions.filter(a => a.fileId === fileId);
    },
    async openEditor(meta) {
      let snippetId = meta.snippetId;
      let hash = meta.hash ?? null;
      let from = meta.from ?? null;
      if (snippetId === null) {
        try {
          // A selection has no snippet or hash yet; creating it returns both, and the hash is what
          // lets the editor offer the full set of actions right away (not just after a reload).
          const data = await resolveSnippetFromFile(meta);
          snippetId = data.snippet;
          if (!hash) hash = data.hash || null;
          if (!from) from = data.from || null;
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
        hash,
        from,
        filePath: meta.filePath ?? null,
        initial: null,
        editingId: null
      });
    },
    async showInlineEditor(payload) {
      if (this.panel?.fileId !== payload.fileId) {
        const target = this.targetForFile(payload.fileId);
        if (target) await this.revealPanel(target);
      }
      this.openInlineEditor = {...payload, key: ++openEditorKeySeq};
      await this.$nextTick();
      const el = document.getElementById('inline-snippet-editor');
      if (el) el.scrollIntoView({block: 'nearest'});
    },
    closeInlineEditor() {
      this.openInlineEditor = null;
    },
    async onIgnoreMatch(meta) {
      // Curator correction path (the menu item is gated on the curate capability in FileSource): stage the
      // ignore in one click instead of opening the editor, since ignoring needs no editing.
      let hash;
      try {
        ({hash} = await resolveMatchChecksum(meta));
      } catch (err) {
        // eslint-disable-next-line no-alert
        alert(err.message ?? String(err));
        return;
      }
      this.pendingActions.push(ignorePendingAction({id: ++pendingActionIdSeq, meta, hash}));
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
    openGlobProposal(panel, create = false) {
      this.globProposalFileId = panel.fileId;
      this.globProposalEditingId = null;
      this.globProposalCreate = create;
      this.$refs.globProposalModal.open({glob: this.suggestGlob(panel.path), reason: '', create});
    },
    onGlobProposalSubmit({glob, reason}) {
      const editingIdx =
        this.globProposalEditingId !== null
          ? this.pendingActions.findIndex(a => a.id === this.globProposalEditingId)
          : -1;
      const baseId = editingIdx >= 0 ? this.pendingActions[editingIdx].id : ++pendingActionIdSeq;
      // Curators add the glob straight to ignored_files (create-glob); everyone else stages a
      // proposal for later review (propose-glob), which is the only difference between the two.
      const formData = this.globProposalCreate
        ? {glob, from: this.packageName, package: this.pkgId}
        : {glob, reason, from: this.packageName, package: this.pkgId};
      const action = {
        id: baseId,
        snippetId: null,
        fileId: this.globProposalFileId,
        startLine: null,
        endLine: null,
        hash: null,
        from: this.packageName,
        action: this.globProposalCreate ? 'create-glob' : 'propose-glob',
        formData,
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
      } else if (event.key === 'u') {
        if (this.missedFiles.length === 0) return;
        event.preventDefault();
        this.scrollToUnresolvedList();
      } else if (event.key === 'c') {
        if (this.licenseCompatibility.licenses.length === 0) return;
        event.preventDefault();
        this.scrollToCompatibility();
      } else if (event.key === '1') {
        event.preventDefault();
        this.setActiveTab('review', {scrollIntoView: true});
      } else if (event.key === '2') {
        event.preventDefault();
        this.setActiveTab('notes', {scrollIntoView: true});
      } else if (event.key === '3') {
        event.preventDefault();
        this.setActiveTab('artifacts', {scrollIntoView: true});
      } else if (event.key === '4') {
        if (this.components.length === 0) return;
        event.preventDefault();
        this.setActiveTab('components', {scrollIntoView: true});
      } else if (event.key === 't') {
        event.preventDefault();
        window.scrollTo({top: 0, behavior: 'smooth'});
      } else if (event.key === 'f') {
        const el = document.getElementById('pkg-review');
        if (!el) return;
        event.preventDefault();
        el.scrollIntoView({behavior: 'smooth', block: 'start'});
      } else if (event.key === '?' || (event.key === '/' && event.shiftKey)) {
        event.preventDefault();
        this.showShortcuts();
      }
    },
    // Steps through the unresolved snippets in the open panel, loads more past the last one shown, and
    // opens the neighbouring file's panel past the end of a file
    async gotoMatch(direction) {
      const starts = () =>
        Array.from(document.querySelectorAll('.report-match-panel:not(.cavil-reveal-leave-active) tr.match-start'));
      const panel = this.panel?.list === 'unresolved' ? this.panel : null;
      let els = panel ? starts() : [];
      let idx = els.findIndex(el => el.id === this.currentMatchId);
      if (idx < 0) idx = direction > 0 ? -1 : els.length;
      let target = els[idx + direction];

      if (!target && direction > 0 && panel?.source && panel.source.total > panel.groups) {
        await this.showMore();
        await this.$nextTick();
        target = starts()[idx + direction];
      }
      if (!target) {
        const files = this.missedFiles;
        const current = panel ? files.findIndex(f => f.name === panel.path) : -1;
        const file = files[current < 0 ? (direction > 0 ? 0 : files.length - 1) : current + direction];
        if (!file) return;
        await this.openPanel(this.unresolvedTarget(file));
        await this.$nextTick();
        els = starts();
        target = direction > 0 ? els[0] : els[els.length - 1];
      }
      if (!target) return;
      this.currentMatchId = target.id;
      target.scrollIntoView({behavior: 'smooth', block: 'center'});
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
      if (action.action === 'propose-glob' || action.action === 'create-glob') {
        const create = action.action === 'create-glob';
        this.globProposalFileId = action.fileId;
        this.globProposalEditingId = action.id;
        this.globProposalCreate = create;
        this.$refs.globProposalModal.open({glob: action.formData.glob, reason: action.formData.reason ?? '', create});
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
        ({res, data, results} = await submitSnippetDecisions(body.actions, {report: this.pkgId}));
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

      // A rebuild started while the batch was being staged, so the server refused it as a whole and nothing
      // was written. The changes are kept exactly as they are; the page switches to its rebuilding state and
      // the reviewer can submit them the moment the new report lands.
      if (data && data.reindexing) {
        for (const action of queue) {
          action.state = 'pending';
          action.error = null;
        }
        this.reindexing = true;
        this.scheduleStatePoll();
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
/* The bar lines up with the sentence above it rather than running edge to edge, so the notice reads as
   one block instead of a panel with a strip stuck to its bottom */
.reindexing-progress {
  padding: 0 0.85rem 0.75rem;
}
.report-tabs {
  align-items: stretch;
  border-bottom: 1px solid var(--cavil-border);
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
  color: var(--cavil-fg-muted);
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
  background: var(--cavil-canvas-tint);
  color: var(--cavil-fg);
}
.report-tab.active {
  background: var(--cavil-canvas);
  border-color: var(--cavil-border);
  color: var(--cavil-fg);
  font-weight: 600;
}
.report-tab-badge {
  background: var(--cavil-neutral-bg);
  border-radius: 10px;
  color: var(--cavil-fg-muted);
  font-size: 11px;
  font-weight: 600;
  line-height: 1;
  padding: 3px 8px;
}
.report-tab.active .report-tab-badge {
  background: var(--cavil-accent-bg);
  color: var(--cavil-accent);
}
.report-tab-badge.report-tab-badge-lawyer {
  background: var(--cavil-attention-bg);
  color: var(--cavil-attention-deep);
}
.report-tab.active .report-tab-badge.report-tab-badge-lawyer {
  background: var(--cavil-attention-tint-3);
  color: var(--cavil-attention-deep-6);
}
.report-tab-content {
  display: block;
}
.report-tab-pane {
  display: none;
  min-width: 0;
  padding-top: 1.5rem;
}
.report-tab-pane.is-active {
  display: block;
}
.risk-license-section {
  margin: 1.75rem 0 1.75rem;
}
.risk-license-section-unresolved {
  margin-top: 0;
}
.risk-license-help-text {
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 8px;
  color: var(--cavil-fg-muted);
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
  border-top: 8px solid var(--cavil-border);
  bottom: -8px;
}
.risk-license-help-text::after {
  border-top: 8px solid var(--cavil-canvas-subtle);
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
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: var(--cavil-fg-muted);
  display: inline-block;
  font-size: 12px;
  font-weight: 500;
  line-height: 1;
  padding: 0.45rem 0.7rem;
  white-space: nowrap;
}
.risk-license-list {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 0 6px 6px 6px;
  list-style: none;
  margin: 0;
  padding: 0;
}
.risk-license-section-unresolved .risk-license-list {
  border-top-right-radius: 0;
}
/* Rounded rows instead of a clipping list, which would cut off line action menus */
.risk-license-item:first-child {
  border-top-left-radius: inherit;
  border-top-right-radius: inherit;
}
.risk-license-item:last-child {
  border-bottom-left-radius: inherit;
  border-bottom-right-radius: inherit;
}
.risk-license-item {
  background: var(--cavil-canvas);
  border-top: 1px solid var(--cavil-border-muted);
  padding: 0.5rem 1rem;
  position: relative;
  transition: background-color 0.15s ease;
}
.risk-license-item:first-child {
  border-top: 0;
}
.risk-license-item:hover {
  background: var(--cavil-canvas-subtle);
}
.risk-license-row {
  align-items: center;
  display: grid;
  gap: 0.75rem;
  grid-auto-flow: column;
  grid-template-columns: minmax(0, 1fr);
}
.license-obligations-toggle {
  align-items: center;
  appearance: none;
  background: transparent;
  border: 0;
  color: var(--cavil-fg-muted);
  display: inline-flex;
  font: inherit;
  font-size: 12px;
  font-weight: 600;
  gap: 0.4rem;
  letter-spacing: 0.01em;
  padding: 0.1rem 0;
}
.license-obligations-toggle:hover,
.license-obligations-toggle:focus-visible {
  color: var(--cavil-accent);
}
.license-obligations-toggle i {
  color: var(--cavil-fg-disabled);
  opacity: 0;
  width: 0.7rem;
}
.license-obligations-toggle:hover i,
.license-obligations-toggle:focus-visible i,
.license-obligations-toggle[aria-expanded='true'] i {
  opacity: 1;
}
.risk-license-label {
  align-items: center;
  display: inline-flex;
  gap: 0.4rem;
  min-width: 0;
}
.risk-license-name {
  color: var(--cavil-fg);
  font-weight: 600;
  line-height: 1.35;
  min-width: 0;
  overflow-wrap: anywhere;
}
/* A license that names nothing identifiable. These sort to the end of every bucket, so softening the name
   there dims one block rather than scattering hard-to-read names through the list, and the licenses Cavil
   could actually name keep the full-strength treatment. Weight and size stay: this is a hint that the row
   matters less, not a warning, and it still has to read as easily as the names above it. */
.risk-license-item.is-catch-all .risk-license-name {
  color: var(--cavil-fg-muted);
}
.risk-license-count {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
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
.risk-license-flags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  margin: 0.4rem 0 0;
}
.risk-license-flag {
  align-items: center;
  background: var(--cavil-attention-bg);
  border: 1px solid var(--cavil-attention-tint-5);
  border-radius: 999px;
  color: var(--cavil-attention-deep-5);
  display: inline-flex;
  font-size: 12px;
  font-weight: 600;
  line-height: 1;
  padding: 0.3rem 0.55rem;
  white-space: nowrap;
}
/* Divider between an expanded obligations panel and the file list, gone with the panel */
.license-obligations + .risk-files {
  border-top: 1px solid var(--cavil-border-muted);
  margin: 0.5rem -1rem 0;
  padding: 0.55rem 1rem 0;
}
.risk-file-list {
  border-left: 1px solid var(--cavil-border);
  color: var(--cavil-fg-muted);
  font-size: 13px;
  list-style: none;
  margin: 0.3rem 0 0.1rem 0.35rem;
  padding-left: 0.9rem;
}
.risk-file-list li {
  align-items: center;
  display: grid;
  gap: 0.55rem;
  grid-template-columns: auto minmax(0, 1fr) auto;
  line-height: 1.35;
  position: relative;
}
.risk-file-list li::before {
  background: var(--cavil-fg-subtle);
  border: 2px solid var(--cavil-canvas);
  border-radius: 50%;
  box-shadow: 0 0 0 1px var(--cavil-border);
  content: '';
  height: 0.45rem;
  margin-left: -1.15rem;
  width: 0.45rem;
}
.risk-file-list li + li {
  margin-top: 0.35rem;
}
.risk-file-list .file-link {
  color: var(--cavil-fg-muted);
  font-size: 13px;
  overflow-wrap: anywhere;
  text-decoration-color: transparent;
}
.risk-file-list .file-link:hover,
.risk-file-list .file-link:focus-visible {
  color: var(--cavil-accent-strong);
  text-decoration-color: currentColor;
}
.risk-file-list .report-match-panel {
  grid-column: 2 / -1;
}
.risk-file-more {
  appearance: none;
  justify-self: start;
  background: none;
  border: 0;
  color: inherit;
  font: inherit;
  padding: 0 0 0 0.95rem;
}
button.risk-file-more {
  cursor: pointer;
}
button.risk-file-more:hover,
button.risk-file-more:focus-visible {
  color: var(--cavil-accent-strong);
}
/* GitHub's file-header chevron, shown on hover and while its panel is open so the lists stay calm */
.file-link-chevron {
  font-size: 9px;
  margin-right: 0.35rem;
  opacity: 0;
  width: 0.6rem;
}
.file-link-chevron::before {
  content: '\f054';
}
.file-link:hover .file-link-chevron,
.file-link:focus-visible .file-link-chevron,
.file-link[aria-expanded='true'] .file-link-chevron {
  opacity: 1;
}
.file-link[aria-expanded='true'] .file-link-chevron::before {
  content: '\f078';
}
/* The open row is a header: no link colour, and no row hover or wash competing with the code below it */
.risk-license-item .file-link[aria-expanded='true'] {
  color: var(--cavil-fg);
  text-decoration-color: transparent;
}
[data-bs-theme] .risk-license-item:has(.report-match-panel),
[data-bs-theme] .risk-license-item:has(.report-match-panel):hover {
  background: var(--cavil-canvas);
  box-shadow: none;
}
.risk-unresolved-list {
  margin-bottom: 0;
}
.risk-unresolved-item {
  background: linear-gradient(90deg, rgba(var(--cavil-attention-strong-rgb), 0.08), var(--cavil-canvas) 2.5rem);
  padding-bottom: 0.5rem;
  padding-top: 0.5rem;
}
.risk-unresolved-item:hover {
  background: linear-gradient(90deg, rgba(var(--cavil-attention-strong-rgb), 0.12), var(--cavil-canvas-subtle) 2.5rem);
}
/* Inset rule rather than a wash, for the same reason as the legal-document rows. */
[data-bs-theme='dark'] .risk-unresolved-item {
  background: var(--cavil-canvas);
  box-shadow: inset 2px 0 0 var(--cavil-attention);
}
[data-bs-theme='dark'] .risk-unresolved-item:hover {
  background: var(--cavil-canvas-subtle);
}
.risk-unresolved-row {
  align-items: center;
  display: grid;
  gap: 0.6rem;
  grid-template-columns: minmax(180px, 1.2fr) minmax(180px, 1fr) auto auto;
}
.risk-unresolved-name {
  align-items: center;
  display: inline-flex;
  gap: 0.4rem;
  min-width: 0;
}
/* A location, not a verdict: muted prose rather than a badge, because "only in vendored files" is
   something to check, and the path classifier is a heuristic that has needed widening more than once. */
.risk-license-scope {
  color: var(--cavil-fg-subtle);
  flex: 0 0 auto;
  font-size: 12px;
}
.risk-new {
  background: var(--cavil-accent-bg);
  border-radius: 999px;
  color: var(--cavil-accent-strong);
  flex: 0 0 auto;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.04em;
  padding: 0.05rem 0.4rem;
  text-transform: uppercase;
}
.risk-unresolved-file {
  color: var(--cavil-fg-muted);
  font-size: 13px;
  font-weight: 500;
  line-height: 1.35;
  min-width: 0;
  overflow-wrap: anywhere;
  text-decoration-color: transparent;
}
.risk-unresolved-file:hover,
.risk-unresolved-file:focus-visible {
  color: var(--cavil-accent-strong);
  text-decoration-color: currentColor;
}
.risk-unresolved-match {
  align-items: center;
  color: var(--cavil-fg-muted);
  display: inline-flex;
  font-size: 13px;
  gap: 0.35rem;
  min-width: 0;
  overflow-wrap: anywhere;
}
.risk-unresolved-match::before {
  background: var(--cavil-attention-strong);
  border-radius: 999px;
  content: '';
  flex: 0 0 auto;
  height: 0.5rem;
  width: 0.5rem;
}
.risk-unresolved-estimate {
  align-items: center;
  color: var(--cavil-fg-muted);
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
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: var(--cavil-fg-muted);
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
  background: var(--cavil-canvas);
  color: var(--cavil-fg);
  text-decoration: none;
}
.report-artifact-label.collapsed {
  border-bottom: 1px solid var(--cavil-border);
  border-radius: 6px;
}
.report-artifact-label.collapsed:hover,
.report-artifact-label.collapsed:focus {
  background: var(--cavil-canvas-subtle);
}
.report-artifact-label-static {
  cursor: default;
}
.report-artifact-label-static:hover,
.report-artifact-label-static:focus {
  background: var(--cavil-canvas-subtle);
  color: var(--cavil-fg-muted);
}
.report-artifact-list {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 0 6px 6px 6px;
  list-style: none;
  margin: 0;
  overflow: hidden;
  padding: 0;
}
.report-artifact-item {
  align-items: center;
  background: var(--cavil-canvas);
  border-top: 1px solid var(--cavil-border-muted);
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
  background: var(--cavil-canvas-subtle);
}
.report-artifact-value {
  color: var(--cavil-fg-muted);
  font-size: 13px;
  font-weight: 500;
  line-height: 1.35;
  min-width: 0;
  overflow-wrap: anywhere;
}
.report-artifact-source {
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
  font-size: 12px;
  font-weight: 600;
  justify-self: end;
  line-height: 1;
  max-width: 100%;
  overflow-wrap: anywhere;
  padding: 0.35rem 0.6rem;
  text-align: right;
}
.report-component-item {
  gap: 0.85rem;
  grid-template-columns: minmax(0, 1fr) auto 5rem auto;
}
.report-component-list {
  border-radius: 6px;
}
.report-component-toolbar {
  margin-bottom: 0.75rem;
}
.report-component-filter {
  flex: 1 1 20rem;
  margin: 0;
  min-width: min(20rem, 100%);
  white-space: nowrap;
}
.report-component-empty {
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  color: var(--cavil-fg-muted);
  font-size: 13px;
  font-weight: 500;
  margin: 0 0 1rem;
  padding: 0.75rem 1rem;
}
.report-component-name {
  color: var(--cavil-fg-emphasis);
  font-size: 13px;
  font-weight: 600;
  min-width: 0;
  overflow-wrap: anywhere;
  text-decoration: none;
}
a.report-component-name {
  color: var(--cavil-fg-emphasis);
}
a.report-component-name:hover,
a.report-component-name:focus {
  text-decoration: underline;
}
.report-component-version {
  color: var(--cavil-fg-muted);
  font-weight: 400;
}
.report-component-license {
  font-size: 13px;
  font-weight: 500;
  overflow-wrap: anywhere;
}
.report-component-search {
  color: var(--cavil-fg-disabled);
  justify-self: end;
  line-height: 1;
}
.report-component-search:hover,
.report-component-search:focus {
  color: var(--cavil-accent);
}
.report-component-ecosystem {
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
  font-size: 11px;
  font-weight: 600;
  justify-self: end;
  letter-spacing: 0.03em;
  line-height: 1;
  padding: 0.3rem 0.55rem;
  text-transform: uppercase;
  white-space: nowrap;
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
  color: var(--cavil-fg-muted);
  font-size: 13px;
  overflow-wrap: anywhere;
  padding: 0;
}
@media (max-width: 700px) {
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
    grid-auto-flow: row;
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
  color: var(--cavil-fg-muted);
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
  border-bottom: 1px solid var(--cavil-neutral-bg);
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
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  box-shadow: inset 0 -1px 0 var(--cavil-border);
  color: var(--cavil-fg);
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', monospace;
  font-size: 0.75rem;
  padding: 3px 6px;
  min-width: 1.5em;
  text-align: center;
  display: inline-block;
}
</style>
