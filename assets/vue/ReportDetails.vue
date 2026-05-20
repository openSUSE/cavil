<template>
  <div>
    <div v-if="loading">
      <ProgressBar v-if="stage" :stage="stage" />
      <div v-else>
        <span id="ajax-status">
          <i class="fa-solid fa-spinner fa-pulse"></i>Preparing the report, this may take a moment...
        </span>
      </div>
    </div>
    <div v-else-if="emptyReport" class="alert alert-success" role="alert">
      No files matching any known license patterns or keywords have been found.
    </div>
    <div v-else>
      <br />
      <div v-if="chart !== null" class="row">
        <div class="col mb-3">
          <canvas id="license-chart" ref="chartCanvas" width="100%" height="18em"></canvas><br />
        </div>
      </div>

      <div v-if="incompatibleLicenses.length > 0" id="incompatible-licenses" class="alert alert-danger">
        <p>Elevated risk, package might contain incompatible licenses:</p>
        <ul>
          <li v-for="(match, idx) in incompatibleLicenses" :key="idx">{{ match.licenses.join(', ') }}</li>
        </ul>
      </div>

      <div v-if="missedFiles.length > 0">
        <div id="incomplete-warning" class="alert alert-warning">
          Report is incomplete, reviewers need to create new license patterns for unmatched keywords or ignore false
          positive matches. Estimated risks for each file are based on the highest risk snippet. The lower its
          similarity to existing license patterns, the higher the risk will climb above the predicted license.
        </div>
        <h4>
          <div class="badge text-bg-dark">Risk 9</div>
        </h4>
        <div class="row">
          <div class="col mb-3" id="unmatched-files">
            <i class="fa-solid fa-circle-exclamation"></i>
            {{ unresolvedMatches }} unique unresolved {{ unresolvedMatches === 1 ? 'match' : 'matches' }} in (at least)
            <span id="unmatched-count">{{ missedFiles.length }}</span>
            {{ missedFiles.length === 1 ? 'file' : 'files' }}
            <div id="filelist-snippets" class="collapse show">
              <table class="table table-borderless m-0 ms-4 hover-table">
                <tbody>
                  <tr v-for="file in missedFiles" :key="file.id">
                    <td class="breakable-column p-0">
                      <a :href="'#file-' + file.id" class="file-link" @click="onFileLinkClick(file.id)">{{
                        file.name
                      }}</a>
                    </td>
                    <td class="p-0">
                      <b>{{ file.match }}%</b> similarity to <b v-html="file.license_html"></b>
                    </td>
                    <td class="static-column p-0 text-end">
                      estimated
                      <div :class="['badge', 'estimated-risk', estimatedRiskClass(file.max_risk)]">
                        Risk {{ file.max_risk }}
                      </div>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>

      <div v-for="risk in sortedRisks" :key="risk">
        <h4>
          <div :class="['badge', riskBadgeClass(risk)]">Risk {{ risk }}</div>
        </h4>
        <ul :id="'risk-' + risk">
          <li v-for="lic in risks[risk]" :key="lic.list_id">
            <span v-html="lic.name_html"></span>:
            <a :href="'#' + lic.list_id" data-bs-toggle="collapse"> {{ lic.files.length }} files </a>
            <p v-if="lic.flags.length > 0">Flags: {{ lic.flags.map(capitalize).join(', ') }}</p>
            <div :id="lic.list_id" :class="lic.list_class">
              <ul>
                <li v-for="file in lic.shown_files" :key="file[0]">
                  <a :href="'#file-' + file[0]" class="file-link" @click="onFileLinkClick(file[0])">{{ file[1] }}</a>
                </li>
                <li v-if="lic.more_files > 0">{{ lic.more_files }} more</li>
              </ul>
            </div>
          </li>
        </ul>
      </div>

      <div v-if="matchingGlobs.length > 0">
        <h2>Files ignored by glob</h2>
        <ul>
          <li v-for="glob in matchingGlobs" :key="glob">{{ glob }}</li>
        </ul>
      </div>

      <div v-if="files.length > 0">
        <h2>Files</h2>
        <div v-for="file in files" :key="file.id" :class="['file-container', {'d-none': !file.expanded}]">
          <a :name="'file-' + file.id"></a>
          <div class="file">
            <a href="#" :id="'expand-link-' + file.id" @click.prevent="toggleExpand(file)">{{ file.path }}</a>
            <div class="float-end">
              <a :href="file.file_url" target="_blank">
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
              :is-admin-or-contributor="isAdminOrContributor"
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
        <br />
      </div>

      <div v-if="emails.length > 0">
        <h2>
          <a href="#emails" data-bs-toggle="collapse">{{ emails.length }} Emails</a>
        </h2>
        <div class="row collapse" id="emails">
          <div class="col">
            <table class="table table-striped transparent-table">
              <tbody>
                <tr v-for="email in emails" :key="email[0]">
                  <td>{{ email[0] }}</td>
                  <td>{{ email[1] }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div v-if="urls.length > 0">
        <h2>
          <a href="#urls" data-bs-toggle="collapse">{{ urls.length }} URLs</a>
        </h2>
        <div class="row collapse" id="urls">
          <div class="col">
            <table class="table table-striped transparent-table">
              <tbody>
                <tr v-for="url in urls" :key="url[0]">
                  <td>{{ url[0] }}</td>
                  <td>{{ url[1] }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <br />
    </div>
    <PendingActionsWidget v-if="isAdminOrContributor && pendingActions.length > 0" />
  </div>
</template>

<script>
import FileSource from './components/FileSource.vue';
import PendingActionsWidget from './components/PendingActionsWidget.vue';
import ProgressBar from './components/ProgressBar.vue';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import Chart from 'chart.js';

let pendingActionIdSeq = 0;
let openEditorKeySeq = 0;

export default {
  name: 'ReportDetails',
  components: {FileSource, PendingActionsWidget, ProgressBar},
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
      chartInstance: null,
      emails: [],
      files: [],
      incompatibleLicenses: [],
      loading: true,
      matchingGlobs: [],
      missedFiles: [],
      openInlineEditor: null,
      pendingActions: [],
      hashHandled: false,
      refreshDelay: 5000,
      refreshUrl: `/reviews/report_details/${this.pkgId}`,
      risks: {},
      stage: null,
      unresolvedMatches: 0,
      urls: []
    };
  },
  computed: {
    sortedRisks() {
      return Object.keys(this.risks).sort((a, b) => Number(b) - Number(a));
    },
    emptyReport() {
      return this.sortedRisks.length === 0 && this.missedFiles.length === 0;
    }
  },
  beforeUnmount() {
    if (this.chartInstance) this.chartInstance.destroy();
  },
  methods: {
    capitalize(str) {
      return str.charAt(0).toUpperCase() + str.slice(1);
    },
    estimatedRiskClass(risk) {
      if (risk === 9) return 'text-bg-dark';
      if (risk > 5) return 'text-bg-danger';
      if (risk === 5) return 'text-bg-warning';
      return 'text-bg-success';
    },
    riskBadgeClass(risk) {
      const r = Number(risk);
      if (r <= 4) return 'text-bg-success';
      if (r === 5) return 'text-bg-warning';
      return 'text-bg-danger';
    },
    refreshData(data) {
      if (data.error) {
        this.loading = true;
        this.stage = data.stage ?? null;
        this.refreshDelay = 5000;
        return;
      }

      this.loading = false;
      this.refreshDelay = 0;
      this.chart = data.chart;
      this.incompatibleLicenses = data.incompatible_licenses;
      this.missedFiles = data.missed_files;
      this.unresolvedMatches = data.package.unresolved_matches;
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
        if (this.chart !== null) {
          this.renderChart();
        } else if (this.chartInstance) {
          this.chartInstance.destroy();
          this.chartInstance = null;
        }
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
    renderChart() {
      const canvas = this.$refs.chartCanvas;
      if (!canvas) return;
      if (this.chartInstance) this.chartInstance.destroy();
      this.chartInstance = new Chart(canvas, {
        type: 'doughnut',
        data: {
          labels: JSON.parse(this.chart.licenses),
          datasets: [
            {
              label: '# of Files',
              data: JSON.parse(this.chart['num-files']),
              backgroundColor: JSON.parse(this.chart.colours)
            }
          ]
        },
        options: {
          legend: {position: 'right'}
        }
      });
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
      const file = this.files.find(f => f.id === id);
      if (!file) return;
      this.scrollToFile(file);
    },
    pendingActionsForFile(fileId) {
      return this.pendingActions.filter(a => a.fileId === fileId);
    },
    async openEditor(meta) {
      let snippetId = meta.snippetId;
      if (snippetId === null) {
        const qs = new URLSearchParams({from: meta.from});
        if (meta.hash) qs.set('hash', meta.hash);
        const url = `/snippets/from_file/${meta.fileId}/${meta.startLine}/${meta.endLine}?${qs.toString()}`;
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.get(url, {headers: {Accept: 'application/json'}});
        if (!res.isSuccess) {
          // eslint-disable-next-line no-alert
          alert(`Could not load snippet (HTTP ${res.statusCode})`);
          return;
        }
        const data = await res.json();
        snippetId = data.snippet;
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
      if (el) el.scrollIntoView({block: 'center'});
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
    async editAction(id) {
      const action = this.pendingActions.find(a => a.id === id);
      if (!action) return;
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
      const ua = new UserAgent({baseURL: window.location.href});
      let res;
      try {
        res = await ua.post('/snippet/batch_decision', {json: body, headers: {Accept: 'application/json'}});
      } catch (err) {
        for (const action of queue) {
          action.state = 'error';
          action.error = err.message ?? String(err);
        }
        return;
      }
      let data = null;
      try {
        data = await res.json();
      } catch (e) {
        // ignore JSON parse errors; handled below
      }
      const results = data && Array.isArray(data.results) ? data.results : [];

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
