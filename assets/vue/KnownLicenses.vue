<template>
  <div>
    <div class="row">
      <cavil-notice-panel intro class="col-12">
        These patterns are used to identify relevant legal text in source code. This may be license text, copyright
        statements, EULAs, CLAs, or other legal text. Patterns without license identifiers (keyword patterns) are used
        to locate potential new license patterns.
      </cavil-notice-panel>
    </div>
    <CavilListLayout
      :current-page="currentPage"
      :end="end"
      :filter="filter"
      count-icon="fa-solid fa-scale-balanced"
      filter-aria-label="License filters"
      filter-input-id="known-licenses-filter-input"
      filter-label="Filter licenses"
      filter-placeholder="Filter licenses"
      plural="licenses"
      singular="license"
      :start="start"
      :total="total"
      :total-pages="totalPages"
      @filter-submit="filterNow"
      @goto-page="gotoPage"
      @update:filter="filter = $event"
    >
      <template #per-page>
        <label class="cavil-list-control">
          <span>Per page</span>
          <select v-model="params.limit" @change="gotoPage(1)" class="form-select">
            <option>10</option>
            <option>25</option>
            <option>50</option>
            <option>100</option>
          </select>
        </label>
      </template>

      <table class="cavil-list-table table">
        <thead>
          <tr>
            <th class="link" style="width: 50%">License</th>
            <th>SPDX</th>
            <th>Risks</th>
          </tr>
        </thead>
        <tbody v-if="licenses === null">
          <tr>
            <td id="all-done" colspan="3" class="cavil-list-state">
              <i class="fa-solid fa-rotate fa-spin"></i> Loading licenses...
            </td>
          </tr>
        </tbody>
        <tbody v-else-if="licenses.length > 0">
          <tr v-for="license in licenses" :key="license.link">
            <td class="cavil-list-primary" v-html="license.link"></td>
            <td v-html="license.spdxHtml"></td>
            <td>
              <span v-for="risk in license.risks" :key="risk" class="badge me-1" :class="badgeClass(risk)">{{
                risk
              }}</span>
            </td>
          </tr>
        </tbody>
        <tbody v-else>
          <tr>
            <td id="all-done" colspan="3" class="cavil-list-empty-cell">
              <EmptyState message="No licenses found." />
            </td>
          </tr>
        </tbody>
      </table>
    </CavilListLayout>
  </div>
</template>

<script>
import CavilListLayout from './components/CavilListLayout.vue';
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import EmptyState from './components/EmptyState.vue';
import {licenseLink} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';

export default {
  name: 'KnownLicenses',
  mixins: [Refresh],
  components: {CavilListLayout, CavilNoticePanel, EmptyState},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      filter: ''
    });

    return {
      end: 0,
      licenses: null,
      params,
      refreshUrl: '/pagination/licenses/known',
      filter: params.filter,
      start: 0,
      total: 0
    };
  },
  computed: {
    totalPages() {
      return Math.ceil(this.total / this.params.limit);
    },
    currentPage() {
      return Math.ceil(this.end / this.params.limit);
    }
  },
  methods: {
    badgeClass(risk) {
      if (risk === 1 || risk === 2 || risk === 3 || risk === 4) return 'text-bg-success';
      if (risk === 5) return 'text-bg-warning';
      if (risk === 6 || risk === 7) return 'text-bg-danger';
      return 'text-bg-dark';
    },
    gotoPage(num) {
      this.cancelApiRefresh();
      const limit = this.params.limit;
      this.params.offset = num * limit - limit;
      this.licenses = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      const licenses = [];
      for (const license of data.page) {
        licenses.push({
          link: licenseLink(license),
          spdx: license.spdx,
          spdxHtml: license.spdx_html,
          risks: license.risks
        });
      }
      this.licenses = licenses;
    },
    filterNow() {
      this.cancelApiRefresh();
      this.licenses = null;
      this.doApiRefresh();
    }
  },
  watch: {
    ...genParamWatchers('limit', 'offset'),
    filter: function (val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>
