<template>
  <div v-if="pkgName === null"><i class="fa-solid fa-rotate fa-spin"></i> Loading package information...</div>
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
          <dd v-if="pkgEmbargoed === true" id="pkg-embargoed">Yes</dd>
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
          <template v-if="history.length > 0">
            <dt>History</dt>
            <dd>
              <a href="#history" class="report-metadata-collapse-link" data-bs-toggle="collapse">
                <span v-if="history.length === 1">1 other review</span>
                <span v-else>{{ history.length }} other reviews</span>
              </a>
            </dd>
          </template>
          <template v-if="externalLink !== null">
            <dt>External link</dt>
            <dd v-html="externalLink"></dd>
          </template>
          <template v-if="requestsHtml !== null">
            <dt>Requests</dt>
            <dd v-html="requestsHtml"></dd>
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
          <dt>SPDX report</dt>
          <dd>
            <a :href="spdxUrl" target="_blank">
              <span v-if="hasSpdxReport === true">available</span>
              <span v-else>not yet generated</span>
            </a>
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
            <dd v-if="unpackedFiles == 1" id="unpacked-files">1 file ({{ unpackedSize }})</dd>
            <dd v-else id="unpacked-files">{{ unpackedFilesWithSeparator }} files ({{ unpackedSize }})</dd>
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
    <div v-if="history.length > 0" class="collapse" id="history">
      <div class="metadata-collapse-inner">
        <ul class="metadata-related-list">
          <li v-for="prev in history" :key="prev.id" class="metadata-related-item">
            <span class="metadata-related-name" v-html="prev.externalLink"></span>
            <span class="metadata-related-pill">{{ prev.result }}</span>
            <span class="metadata-related-pill">{{ prev.state }}</span>
            <span class="metadata-related-user">{{ prev.reviewing_user }}</span>
            <a :href="prev.reportUrl" class="metadata-related-date" target="_blank">{{ prev.created }}</a>
          </li>
        </ul>
      </div>
    </div>
    <div v-if="pkgFiles.length > 0" id="spec-files" class="collapse">
      <div class="metadata-collapse-inner">
        <ul class="metadata-file-list">
          <li v-for="file in pkgFiles" :key="file.file" class="metadata-file-item">
            <h3 class="metadata-file-title"><i class="fa-solid fa-file-lines"></i> {{ file.file }}</h3>
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
      <pre class="review-information-card-body">{{ notice }}</pre>
    </section>
    <cavil-notice-panel
      v-if="errors.length > 0"
      id="spec-errors"
      icon="fa-solid fa-triangle-exclamation"
      :items="errors"
      title="Package file warnings for packagers"
      tone="warning"
    />
    <cavil-notice-panel
      v-if="warnings.length > 0"
      id="spec-warnings"
      icon="fa-solid fa-clipboard-check"
      :items="warnings"
      title="Package file warnings for reviewers"
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
    <div v-if="hasAdminRole === true" class="metadata-review-section">
      <form :action="reviewUrl" method="POST" class="container metadata-review-form" id="pkg-review">
        <div class="col metadata-review-editor">
          <label class="form-label" for="comment">Comment</label>
          <textarea v-model="result" name="comment" placeholder="Reviewed ok" rows="10" class="form-control"></textarea>
        </div>
        <div class="col mb-3 metadata-review-actions">
          <div class="metadata-review-actions-group">
            <input
              class="btn btn-success"
              id="acceptable_by_lawyer"
              name="acceptable_by_lawyer"
              type="submit"
              value="Acceptable by Lawyer"
            />
            <span v-if="hasLawyerRole === false">
              <input class="btn btn-warning" id="acceptable" name="acceptable" type="submit" value="Acceptable" />
            </span>
            <input class="btn btn-danger" id="unacceptable" name="unacceptable" type="submit" value="Unacceptable" />
          </div>
          <button
            type="button"
            :class="['btn', reindexBtnVariant, 'metadata-review-actions-secondary']"
            :title="reindexTitle"
            :disabled="reindexBusy"
            id="reindex_button"
            @click="reindex"
          >
            Reindex
          </button>
        </div>
      </form>
    </div>
    <div v-else-if="hasManagerRole === true" class="metadata-review-section">
      <form :action="fasttrackUrl" method="POST" class="container metadata-review-form" id="pkg-review">
        <div class="col metadata-review-editor">
          <label class="form-label" for="comment">Comment</label>
          <textarea v-model="result" name="comment" placeholder="Reviewed ok" rows="10" class="form-control"></textarea>
        </div>
        <div class="col mb-3 metadata-review-actions">
          <div class="metadata-review-actions-group">
            <input class="btn btn-warning" id="acceptable" name="acceptable" type="submit" value="Acceptable" />
          </div>
        </div>
      </form>
    </div>
    <div v-else class="metadata-review-section">
      <form class="container metadata-review-form" id="pkg-review">
        <div class="col metadata-review-editor">
          <label class="form-label" for="comment">Comment</label>
          <textarea v-model="result" name="comment" rows="10" class="form-control" disabled></textarea>
        </div>
      </form>
    </div>
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
  </div>
</template>

<script>
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import CopyableText from './components/CopyableText.vue';
import {externalLink, productLink} from './helpers/links.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'ReportMetadata',
  components: {CavilNoticePanel, CopyableText},
  mixins: [Refresh],
  data() {
    return {
      actions: [],
      checkoutUrl: null,
      copiedFiles: {'%doc': null, '%license': null},
      created: null,
      errors: [],
      externalLink: null,
      fasttrackUrl: `/reviews/fasttrack_package/${this.pkgId}`,
      hasSpdxReport: false,
      history: [],
      legalReviewNotices: [],
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
      reindexBusy: false,
      reindexFailed: false,
      requestsHtml: null,
      result: '',
      reviewed: null,
      reviewingUser: null,
      reviewUrl: `/reviews/review_package/${this.pkgId}`,
      searchUrl: null,
      spdxUrl: `/spdx/${this.pkgId}`,
      state: null,
      unpackedFiles: 0,
      unpackedSize: 'n/a',
      warnings: []
    };
  },
  computed: {
    unpackedFilesWithSeparator() {
      return this.unpackedFiles.toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
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
      if (this.pkgRisk === '6') return 'Obligations';
      if (this.pkgRisk === '7') return 'Non-Commercial';
      return 'Unknown Risk';
    },
    stateBadgeClass() {
      if (this.state === 'new') return 'text-bg-secondary';
      if (this.state === 'acceptable_by_lawyer') return 'text-bg-success';
      if (this.state === 'acceptable') return 'text-bg-warning';
      return 'text-bg-danger';
    },
    reindexBtnVariant() {
      if (this.reindexFailed) return 'btn-outline-danger';
      return this.shouldReindex ? 'btn-outline-primary' : 'btn-outline-secondary';
    },
    reindexTitle() {
      if (this.reindexFailed) return 'Reindex request failed';
      return this.shouldReindex ? 'There are new patterns!' : 'There are no new patterns';
    }
  },
  methods: {
    async reindex() {
      this.reindexBusy = true;
      this.reindexFailed = false;
      try {
        const response = await fetch(this.reindexUrl, {method: 'POST', cache: 'no-store'});
        if (response.ok) {
          window.location.reload();
          return;
        }
      } catch (err) {
        console.error('Reindex request failed:', err);
      }
      this.reindexBusy = false;
      this.reindexFailed = true;
    },
    refreshData(data) {
      const copiedFiles = data.copied_files;
      if (copiedFiles['%doc'].length > 0) this.copiedFiles['%doc'] = copiedFiles['%doc'].join(' ');
      if (copiedFiles['%license'].length > 0) this.copiedFiles['%license'] = copiedFiles['%license'].join(' ');

      this.created = moment(data.created * 1000).fromNow();
      this.errors = data.errors;
      this.externalLink = externalLink({external_link: data.external_link});
      this.hasSpdxReport = data.has_spdx_report;
      this.legalReviewNotices = data.legal_review_notices;

      this.actions = data.actions;
      for (const action of this.actions) {
        action.created = moment(action.created * 1000).fromNow();
        action.actionUrl = `/reviews/details/${action.id}`;
      }

      this.history = data.history;
      for (const prev of this.history) {
        prev.created = moment(prev.created * 1000).fromNow();
        prev.externalLink = externalLink({external_link: prev.external_link});
        prev.reportUrl = `/reviews/details/${prev.id}`;
      }

      this.pkgFiles = data.package_files;
      for (const file of this.pkgFiles) {
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

      if (data.products.length > 0) {
        this.productsHtml = data.products.map(name => productLink({name})).join(', ');
      }
      if (data.requests.length > 0) {
        this.requestsHtml = data.requests.map(req => externalLink({external_link: req})).join(', ');
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

      this.warnings = data.warnings;
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
  color: #1f2328;
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
  color: #6e7781;
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
.report-metadata-list a {
  color: #0969da;
  text-decoration: none;
  text-underline-offset: 2px;
}
.report-metadata-list a:hover,
.report-metadata-list a:focus {
  text-decoration: underline;
}
.report-metadata-list small {
  color: #8c959f;
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
.report-metadata-id {
  border-radius: 6px;
  color: #1f2328;
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 14px;
  padding: 0.05rem 0.35rem;
  transition:
    background-color 0.15s ease,
    color 0.15s ease;
}
.report-metadata-id:hover,
.report-metadata-id:focus {
  background: #f6f8fa;
  color: #0969da;
  outline: none;
}
.report-metadata-collapse-link {
  border-bottom: 1px dashed #afb8c1;
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
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 999px;
  color: #57606a;
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
  background: #eef6ff;
  border-color: #b6e3ff;
  color: #0969da;
  text-decoration: none;
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
  background: #ffffff;
  border: 1px solid #d0d7de;
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
  background: #f6f8fa;
}
.metadata-related-name {
  color: #1f2328;
  font-size: 13px;
  font-weight: 600;
  min-width: 0;
  overflow-wrap: anywhere;
}
.metadata-related-pill {
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 999px;
  color: #57606a;
  font-size: 12px;
  font-weight: 600;
  line-height: 1;
  padding: 0.35rem 0.6rem;
  white-space: nowrap;
}
.metadata-related-user,
.metadata-related-date {
  color: #57606a;
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
  color: #0550ae;
  text-decoration-color: currentColor;
}
.metadata-file-item {
  background: #ffffff;
  border: 1px solid #d0d7de;
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
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  color: #1f2328;
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
  color: #6e7781;
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
  color: #57606a;
  font-weight: 600;
}
.metadata-file-details dd {
  color: #1f2328;
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
  background: #ffffff;
  border: 1px solid #1f2328;
  border-radius: 6px;
  margin: 1.25rem 0;
  overflow: hidden;
}
.review-information-card-bar {
  align-items: center;
  background: #1f2328;
  color: #d0d7de;
  display: flex;
  font-size: 12px;
  font-weight: 500;
  gap: 0.45rem;
  letter-spacing: 0.04em;
  padding: 0.45rem 0.85rem;
  text-transform: lowercase;
}
.review-information-card-bar i {
  color: #7d8590;
  font-size: 11px;
}
.review-information-card-body {
  color: #1f2328;
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
.metadata-review-editor {
  background: #ffffff;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  overflow: hidden;
}
.metadata-review-editor .form-label {
  align-items: center;
  background: #f6f8fa;
  border-bottom: 1px solid #d0d7de;
  color: #1f2328;
  display: flex;
  font-size: 13px;
  font-weight: 600;
  margin: 0;
  min-height: 2.25rem;
  padding: 0.45rem 0.75rem;
}
.metadata-review-editor .form-control {
  background: #ffffff;
  border: 0;
  border-radius: 0;
  box-shadow: none;
  color: #1f2328;
  font-size: 14px;
  line-height: 1.45;
  min-height: 12rem;
  padding: 0.75rem;
  resize: vertical;
}
.metadata-review-editor:focus-within {
  border-color: #0969da;
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.18);
}
.metadata-review-editor .form-control:focus {
  box-shadow: none;
  outline: none;
}
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
  background-color: #0b374d;
  color: #ffffff;
  width: 150px;
}
.cavil-package-format-icon i {
  color: #6c757d;
}

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
  --cavil-ribbon-bg-color: #57606a;
}
.cavil-ribbon {
  color: var(--cavil-ribbon-color, #fff);
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
