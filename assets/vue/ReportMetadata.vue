<template>
  <div v-if="pkgName === null"><i class="fa-solid fa-rotate fa-spin"></i> Loading package information...</div>
  <div v-else>
    <div class="row">
      <div class="col-10 mt-3">
        <h2 v-if="pkgName !== null">
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
        <table class="table borderless novertpad">
          <tbody>
            <tr v-if="pkgLicense !== null && pkgLicense.name !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-box"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">License:</th>
              <td id="pkg-license">
                {{ pkgLicense.name }}
                <small v-if="pkgLicense.spdx === false">(not SPDX)</small>
              </td>
            </tr>
            <tr>
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-lock"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Embargoed:</th>
              <td v-if="pkgEmbargoed === true" id="pkg-embargoed">Yes</td>
              <td v-else id="pkg-embargoed">No</td>
            </tr>
            <tr v-if="state !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-balance-scale"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">State:</th>
              <td id="pkg-state">
                <div v-if="state === 'new'" class="badge text-bg-secondary">{{ state }}</div>
                <div v-else-if="state === 'acceptable_by_lawyer'" class="badge text-bg-success">{{ state }}</div>
                <div v-else-if="state === 'acceptable'" class="badge text-bg-warning">{{ state }}</div>
                <div v-else class="badge text-bg-danger">{{ state }}</div>
              </td>
            </tr>
            <tr v-if="pkgFiles.length > 0">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-cubes"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Package Files:</th>
              <td id="num-spec-files">
                <a v-if="pkgFiles.length === 1" href="#spec-files" class="metadata-count-pill" data-bs-toggle="collapse"
                  >1 file</a
                >
                <a v-else href="#spec-files" class="metadata-count-pill" data-bs-toggle="collapse"
                  >{{ pkgFiles.length }} files</a
                >
              </td>
            </tr>
            <tr v-if="actions.length > 0">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-directions"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Actions:</th>
              <td>
                <a v-if="actions.length === 1" href="#actions" class="metadata-count-pill" data-bs-toggle="collapse"
                  >1 related review</a
                >
                <a v-else href="#actions" class="metadata-count-pill" data-bs-toggle="collapse"
                  >{{ actions.length }} related reviews</a
                >
              </td>
            </tr>
            <tr v-if="history.length > 0">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-history"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">History:</th>
              <td>
                <a v-if="history.length === 1" href="#history" class="metadata-count-pill" data-bs-toggle="collapse"
                  >1 other review</a
                >
                <a v-else href="#history" class="metadata-count-pill" data-bs-toggle="collapse"
                  >{{ history.length }} other reviews</a
                >
              </td>
            </tr>
            <tr v-if="externalLink !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-anchor"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">External Link:</th>
              <td v-html="externalLink"></td>
            </tr>
            <tr v-if="requestsHtml !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-link"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Requests:</th>
              <td v-html="requestsHtml"></td>
            </tr>
            <tr v-if="productsHtml !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-shopping-bag"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Products:</th>
              <td v-html="productsHtml"></td>
            </tr>
            <tr v-if="pkgVersion !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-code-branch"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Version:</th>
              <td id="pkg-version">{{ pkgVersion }}</td>
            </tr>
            <tr v-if="pkgSummary !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-pen-to-square"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Summary:</th>
              <td id="pkg-summary">{{ pkgSummary }}</td>
            </tr>
            <tr v-if="pkgGroup !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-users"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Group:</th>
              <td id="pkg-group">{{ pkgGroup }}</td>
            </tr>
            <tr v-if="pkgUrl !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-link"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">URL:</th>
              <td id="pkg-url">
                <a :href="pkgUrl" target="_blank">{{ pkgUrl }}</a>
              </td>
            </tr>
            <tr>
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-regular fa-chart-column"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">SPDX Report:</th>
              <td>
                <a :href="spdxUrl" target="_blank">
                  <span v-if="hasSpdxReport === true">available</span>
                  <span v-else>not yet generated</span>
                </a>
              </td>
            </tr>
            <tr v-if="pkgShortname !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-regular fa-file"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Shortname:</th>
              <td id="pkg-shortname">{{ pkgShortname }}</td>
            </tr>
            <tr v-if="checkoutUrl !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-regular fa-folder"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Checkout:</th>
              <td id="checkout-url">
                <a :href="checkoutUrl" target="_blank">{{ pkgChecksum }}</a>
              </td>
            </tr>
            <tr v-if="unpackedFiles > 0">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-sitemap"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Unpacked:</th>
              <td v-if="unpackedFiles == 1" id="unpacked-files">1 file ({{ unpackedSize }})</td>
              <td v-else id="unpacked-files">{{ unpackedFilesWithSeparator }} files ({{ unpackedSize }})</td>
            </tr>
            <tr v-if="pkgPriority !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-regular fa-star"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Priority:</th>
              <td id="pkg-priority">{{ pkgPriority }}</td>
            </tr>
            <tr v-if="created !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-regular fa-square-plus"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Created:</th>
              <td class="from-now">{{ created }}</td>
            </tr>
            <tr v-if="reviewed !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-search"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Reviewed:</th>
              <td class="from-now">{{ reviewed }}</td>
            </tr>
            <tr v-if="reviewingUser !== null">
              <th class="fit text-start noleftpad" scope="row">
                <i class="fa-solid fa-user"></i>
              </th>
              <th class="fit text-start noleftpad" scope="row">Reviewing User:</th>
              <td>
                {{ reviewingUser }}
                <span v-if="pkgAiAssisted" class="ai-assisted-badge"
                  >(with AI Assistant <i class="fa-solid fa-robot"></i>)</span
                >
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="col-2">
        <div v-if="pkgRisk !== null" class="cavil-ribbon float-end" :class="ribbonColor">
          <div class="cavil-ribbon-risk">{{ pkgRisk }}</div>
          <div class="cavil-ribbon-description">{{ ribbonDescription }}</div>
        </div>
      </div>
    </div>
    <div v-if="actions.length > 0" class="collapse metadata-related-panel" id="actions">
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
    <div v-if="history.length > 0" class="collapse metadata-related-panel" id="history">
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
    <div v-if="pkgFiles.length > 0" id="spec-files" class="collapse">
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
    <cavil-notice-panel v-if="notice !== null" icon="fa-solid fa-circle-info" title="Review information" tone="info">
      <pre class="cavil-notice-pre">{{ notice }}</pre>
    </cavil-notice-panel>
    <div v-if="hasAdminRole === true" class="metadata-review-section">
      <form :action="reviewUrl" method="POST" class="container metadata-review-form" id="pkg-review">
        <div class="col metadata-review-editor">
          <label class="form-label" for="comment">Comment</label>
          <textarea v-model="result" name="comment" placeholder="Reviewed ok" rows="10" class="form-control"></textarea>
        </div>
        <div class="col mb-3 metadata-review-actions">
          <input
            class="btn btn-success"
            id="acceptable_by_lawyer"
            name="acceptable_by_lawyer"
            type="submit"
            value="Acceptable by Lawyer"
          />&nbsp;
          <span v-if="hasLawyerRole === false">
            <input class="btn btn-warning" id="acceptable" name="acceptable" type="submit" value="Acceptable" />&nbsp;
          </span>
          <input class="btn btn-danger" id="unacceptable" name="unacceptable" type="submit" value="Unacceptable" />
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
          <input class="btn btn-warning" id="acceptable" name="acceptable" type="submit" value="Acceptable" />
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
import {externalLink, productLink} from './helpers/links.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'ReportMetadata',
  components: {CavilNoticePanel},
  mixins: [Refresh],
  data() {
    return {
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
      if (this.pkgRisk === '6' || this.pkgRisk === '7') return 'cavil-red-ribbon';
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
    }
  },
  methods: {
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
.borderless.novertpad th.fit:first-child i {
  color: #6e7781;
  font-size: 0.95em;
}
.borderless.novertpad th,
.borderless.novertpad td {
  line-height: 1.35;
  padding-bottom: 0.28rem !important;
  padding-top: 0.28rem !important;
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
.metadata-related-panel,
#spec-files {
  margin: 0.85rem 0 1.1rem;
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
  gap: 0;
  margin-top: 0.75rem;
}
.metadata-review-actions .btn {
  border-radius: 6px;
  font-size: 13px;
  font-weight: 600;
  position: relative;
}
.metadata-review-actions span {
  display: inline-flex;
}
.metadata-review-actions > * + * {
  margin-left: -1px;
}
.metadata-review-actions > *:not(:first-child) .btn,
.metadata-review-actions > .btn:not(:first-child) {
  border-bottom-left-radius: 0;
  border-top-left-radius: 0;
}
.metadata-review-actions > *:not(:last-child) .btn,
.metadata-review-actions > .btn:not(:last-child) {
  border-bottom-right-radius: 0;
  border-top-right-radius: 0;
}
.metadata-review-actions .btn:hover,
.metadata-review-actions .btn:focus {
  z-index: 1;
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
  --cavil-ribbon-bg-color: #6c757d;
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
