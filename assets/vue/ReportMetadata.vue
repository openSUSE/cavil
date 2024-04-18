<template>
  <div v-if="pkgName === null"><i class="fas fa-sync fa-spin"></i> Loading package information...</div>
  <div v-else>
    <div class="float-end format">
      <i class="fab fa-suse" v-if="pkgType === 'spec'"></i>
      <i class="fas fa-kiwi-bird" v-else-if="pkgType === 'kiwi'"></i>
      <i class="fab fa-docker" v-else-if="pkgType === 'docker'"></i>
      <i class="fas fa-dharmachakra" v-else-if="pkgType === 'helm'"></i>
      <i class="far fa-question-circle" v-else></i>
    </div>
    <h2 v-if="pkgName !== null">
      <a :href="searchUrl" target="_blank">{{ pkgName }}</a>
    </h2>
    <table class="table borderless novertpad">
      <tbody>
        <tr v-if="state !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-balance-scale"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">State:</th>
          <td id="pkg-state">
            <div v-if="state === 'new'" class="badge text-bg-secondary">{{ state }}</div>
            <div v-else-if="state === 'correct'" class="badge text-bg-success">{{ state }}</div>
            <div v-else-if="state === 'acceptable'" class="badge text-bg-warning">{{ state }}</div>
            <div v-else class="badge text-bg-danger">{{ state }}</div>
          </td>
        </tr>
        <tr v-if="pkgLicense !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-box"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">License:</th>
          <td id="pkg-license">
            {{ pkgLicense.name }}
            <small v-if="pkgLicense.spdx === false">(not SPDX)</small>
          </td>
        </tr>
        <tr v-if="pkgFiles.length > 0">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-cubes"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Package Files:</th>
          <td id="num-spec-files">
            <a v-if="actions.length === 1" href="#spec-files" data-bs-toggle="collapse">1 file</a>
            <a v-else href="#spec-files" data-bs-toggle="collapse">{{ pkgFiles.length }} files</a>
          </td>
        </tr>
        <tr v-if="actions.length > 0">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-directions"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Actions:</th>
          <td>
            <a v-if="actions.length === 1" href="#actions" data-bs-toggle="collapse">1 related review</a>
            <a v-else href="#actions" data-bs-toggle="collapse">{{ actions.length }} related reviews</a>
          </td>
        </tr>
        <tr v-if="history.length > 0">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-history"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">History:</th>
          <td>
            <a v-if="history.length === 1" href="#history" data-bs-toggle="collapse">1 other review</a>
            <a v-else href="#history" data-bs-toggle="collapse">{{ history.length }} other reviews</a>
          </td>
        </tr>
        <tr v-if="externalLink !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-anchor"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">External Link:</th>
          <td v-html="externalLink"></td>
        </tr>
        <tr v-if="requestsHtml !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-link"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Requests:</th>
          <td v-html="requestsHtml"></td>
        </tr>
        <tr v-if="productsHtml !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-shopping-bag"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Products:</th>
          <td v-html="productsHtml"></td>
        </tr>
        <tr v-if="pkgVersion !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-code-branch"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Version:</th>
          <td id="pkg-version">{{ pkgVersion }}</td>
        </tr>
        <tr v-if="pkgSummary !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-edit"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Summary:</th>
          <td id="pkg-summary">{{ pkgSummary }}</td>
        </tr>
        <tr v-if="pkgGroup !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-users"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Group:</th>
          <td id="pkg-group">{{ pkgGroup }}</td>
        </tr>
        <tr v-if="pkgUrl !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-link"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">URL:</th>
          <td id="pkg-url">
            <a :href="pkgUrl" target="_blank">{{ pkgUrl }}</a>
          </td>
        </tr>
        <tr>
          <th class="fit text-start noleftpad" scope="row">
            <i class="far fa-chart-bar"></i>
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
            <i class="far fa-file"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Shortname:</th>
          <td id="pkg-shortname">{{ pkgShortname }}</td>
        </tr>
        <tr v-if="checkoutUrl !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="far fa-folder"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Checkout:</th>
          <td id="checkout-url">
            <a :href="checkoutUrl" target="_blank">{{ pkgChecksum }}</a>
          </td>
        </tr>
        <tr v-if="pkgPriority !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="far fa-star"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Priority:</th>
          <td id="pkg-priority">{{ pkgPriority }}</td>
        </tr>
        <tr v-if="created !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="far fa-plus-square"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Created:</th>
          <td class="from-now">{{ created }}</td>
        </tr>
        <tr v-if="reviewed !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-search"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Reviewed:</th>
          <td class="from-now">{{ reviewed }}</td>
        </tr>
        <tr v-if="reviewingUser !== null">
          <th class="fit text-start noleftpad" scope="row">
            <i class="fas fa-user"></i>
          </th>
          <th class="fit text-start noleftpad" scope="row">Reviewing User:</th>
          <td>{{ reviewingUser }}</td>
        </tr>
      </tbody>
    </table>
    <div v-if="actions.length > 0" class="row collapse" id="actions">
      <div class="col">
        <table class="table table-striped transparent-table">
          <tbody>
            <tr v-for="action in actions" :key="action.id">
              <td>{{ action.name }}</td>
              <td>{{ action.result }}</td>
              <td>{{ action.state }}</td>
              <td>{{ action.reviewing_user }}</td>
              <td class="text-end">
                <a :href="action.actionUrl" target="_blank">{{ action.created }}</a>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    <div v-if="history.length > 0" class="row collapse" id="history">
      <div class="col">
        <table class="table table-striped transparent-table">
          <tbody>
            <tr v-for="prev in history" :key="prev.id">
              <td v-html="prev.externalLink"></td>
              <td>{{ prev.result }}</td>
              <td>{{ prev.state }}</td>
              <td>{{ prev.reviewing_user }}</td>
              <td class="text-end">
                <a :href="prev.reportUrl" target="_blank">{{ prev.created }}</a>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    <div v-if="pkgFiles.length > 0" id="spec-files" class="collapse">
      <div class="alert alert-secondary">
        <table class="table borderless transparent-table">
          <tbody>
            <tr v-for="file in pkgFiles" :key="file.file">
              <td class="noleftpad">
                <table class="table borderless transparent-table">
                  <tr>
                    <th class="fit text-start noleftpad" colspan="2">
                      <i class="fas fa-file-alt"></i> {{ file.file }}
                    </th>
                  </tr>
                  <tr v-if="file.licenses !== null">
                    <th class="fit text-start align-top noleftpad">Licenses:</th>
                    <td>{{ file.licenses }}</td>
                  </tr>
                  <tr v-if="file.version !== null">
                    <th class="fit text-start align-top noleftpad">Version:</th>
                    <td>{{ file.version }}</td>
                  </tr>
                  <tr v-if="file.summary !== null">
                    <th class="fit text-start align-top noleftpad">Summary:</th>
                    <td>{{ file.summary }}</td>
                  </tr>
                  <tr v-if="file.group !== null">
                    <th class="fit text-start align-top noleftpad">Group:</th>
                    <td>{{ file.group }}</td>
                  </tr>
                  <tr v-if="file.url !== null">
                    <th class="fit text-start align-top noleftpad">URL:</th>
                    <td class="text-start">
                      <a :href="file.url" class="p-0" target="_blank">{{ file.url }}</a>
                    </td>
                  </tr>
                  <tr v-if="file.sources !== null">
                    <th class="fit text-start align-top noleftpad">Sources:</th>
                    <td>{{ file.sources }}</td>
                  </tr>
                </table>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    <div v-if="errors.length > 0" id="spec-errors" class="alert alert-warning">
      <p>Package file warnings for packagers:</p>
      <ul>
        <li v-for="error in errors" :key="error">{{ error }}</li>
      </ul>
    </div>
    <div v-if="warnings.length > 0" id="spec-warnings" class="alert alert-warning">
      <p>Package file warnings for reviewers:</p>
      <ul>
        <li v-for="warning in warnings" :key="warning">{{ warning }}</li>
      </ul>
    </div>
    <div v-if="hasAdminRole === true" class="row">
      <form :action="reviewUrl" method="POST" class="container" id="pkg-review">
        <div class="col mb-3">
          <label class="form-label" for="comment">Comment</label>
          <textarea v-model="result" name="comment" rows="10" class="form-control"></textarea>
        </div>
        <div class="col mb-3">
          <input class="btn btn-success" id="correct" name="correct" type="submit" value="Checked" />&nbsp;
          <input class="btn btn-warning" id="acceptable" name="acceptable" type="submit" value="Good Enough" />&nbsp;
          <input class="btn btn-danger" id="unacceptable" name="unacceptable" type="submit" value="Unacceptable" />
        </div>
      </form>
    </div>
    <div v-else-if="hasManagerRole === true" class="row">
      <form :action="fasttrackUrl" method="POST" class="container" id="pkg-review">
        <div class="col mb-3">
          <label class="form-label" for="comment">Comment</label>
          <textarea v-model="result" name="comment" rows="10" class="form-control"></textarea>
        </div>
        <div class="col mb-3">
          <input class="btn btn-warning" id="acceptable" name="acceptable" type="submit" value="Good Enough" />
        </div>
      </form>
    </div>
    <div v-else class="row">
      <form class="container" id="pkg-review">
        <div class="col mb-3">
          <label class="form-label" for="comment">Comment</label>
          <textarea v-model="result" name="comment" rows="10" class="form-control" disabled></textarea>
        </div>
      </form>
    </div>
    <div
      v-if="copiedFiles['%doc'] !== null || copiedFiles['%license'] !== null"
      class="alert alert-secondary top-buffer"
    >
      <p v-if="copiedFiles['%doc'] !== null">
        <b>Files copied as %doc:</b>
        {{ copiedFiles['%doc'] }}
      </p>
      <p v-if="copiedFiles['%license'] !== null">
        <b>Files copied as %license:</b>
        {{ copiedFiles['%license'] }}
      </p>
    </div>
  </div>
</template>

<script>
import {externalLink, productLink} from './helpers/links.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'ReportMetadata',
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
      pkgChecksum: null,
      pkgFiles: [],
      pkgLicense: null,
      pkgName: null,
      pkgPriority: null,
      pkgShortname: null,
      pkgSummary: null,
      pkgType: null,
      pkgUrl: null,
      pkgVersion: null,
      productsHtml: null,
      refreshDelay: 30000,
      refreshUrl: `/reviews/meta/${this.pkgId}`,
      requestsHtml: null,
      result: 'Reviewed ok',
      reviewed: null,
      reviewingUser: null,
      reviewUrl: `/reviews/review_package/${this.pkgId}`,
      searchUrl: null,
      spdxUrl: `/spdx/${this.pkgId}`,
      state: null,
      warnings: []
    };
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
      this.pkgShortname = data.package_shortname;
      this.pkgSummary = data.package_summary;
      this.pkgType = data.package_type;
      this.pkgUrl = data.package_url;
      this.pkgVersion = data.package_version;

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
      const defaultResult = this.hasManagerRole === true || this.hasAdminRole === true ? 'Reviewed ok' : '';
      if (data.state !== this.state) this.result = data.result ?? defaultResult;
      this.state = data.state;
      this.warnings = data.warnings;
    }
  }
};
</script>

<style>
.transparent-table {
  --bs-table-bg: transparent !important;
}
#spec-files table {
  margin: 0;
}
#spec-files table + table {
  margin-top: 1rem;
}
</style>
