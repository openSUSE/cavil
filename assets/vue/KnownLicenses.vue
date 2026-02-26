<template>
  <div class="mt-3">
    <div>
      <form>
        <div class="row g-4">
          <div class="col-lg-2">
            <div class="form-floating">
              <select v-model="params.limit" @change="gotoPage(1)" class="form-control">
                <option>10</option>
                <option>25</option>
                <option>50</option>
                <option>100</option>
              </select>
              <label class="form-label">Licenses per Page</label>
            </div>
          </div>
          <div class="col"></div>
          <div id="cavil-pkg-filter" class="col-lg-3">
            <form @submit.prevent="filterNow">
              <div class="form-floating">
                <input v-model="filter" type="text" class="form-control" placeholder="Filter" />
                <label class="form-label">Filter</label>
              </div>
            </form>
          </div>
        </div>
      </form>
      <div class="row">
        <div class="col-12">
          <table class="table table-striped table-bordered">
            <thead>
              <tr>
                <th class="link" style="width: 50%">License</th>
                <th>SPDX</th>
                <th>Risks</th>
              </tr>
            </thead>
            <tbody v-if="licenses === null">
              <tr>
                <td id="all-done" colspan="4"><i class="fas fa-sync fa-spin"></i> Loading licenses...</td>
              </tr>
            </tbody>
            <tbody v-else-if="licenses.length > 0">
              <tr v-for="license in licenses" :key="license.link">
                <td v-html="license.link"></td>
                <td v-html="license.spdx"></td>
                <td>
                  <span v-for="risk in license.risks" :key="risk" class="badge me-1" :class="badgeClass(risk)">{{
                    risk
                  }}</span>
                </td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr>
                <td id="all-done" colspan="4">No licenses found.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <div class="row">
        <div class="col-6 mb-4">
          <ShownEntries :end.sync="end" :start.sync="start" :total.sync="total" />
        </div>
        <div class="col-6 mb-4" id="cavil-pagination">
          <PaginationLinks
            @goto-page="gotoPage"
            :end.sync="end"
            :start.sync="start"
            :total.sync="total"
            :current-page.sync="currentPage"
            :total-pages.sync="totalPages"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import PaginationLinks from './components/PaginationLinks.vue';
import ShownEntries from './components/ShownEntries.vue';
import {licenseLink} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';

export default {
  name: 'KnownLicenses',
  mixins: [Refresh],
  components: {PaginationLinks, ShownEntries},
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
      if (risk === 1 || risk === 2 || risk === 3) return 'text-bg-success';
      if (risk === 4) return 'text-bg-warning';
      if (risk === 5 || risk === 6) return 'text-bg-danger';
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

<style>
.table {
  margin-top: 1rem;
}
#cavil-pkg-filter form {
  margin: 2px 0;
  white-space: nowrap;
  justify-content: flex-end;
}
#all-done {
  text-align: center;
}
</style>
