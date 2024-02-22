<template>
  <div>
    <div>
      <div class="row">
        <div class="col-sm-12 col-md-8">
          <form class="form-inline">
            <div class="form-group mb-2 mr-sm-4">
              <label
                >Show&nbsp;
                <select v-model="params.limit" @change="gotoPage(1)" class="form-control">
                  <option>10</option>
                  <option>25</option>
                  <option>50</option>
                  <option>100</option>
                </select>
                &nbsp;entries</label
              >
            </div>
            <div class="form-check mb-2 mr-sm-2"></div>
          </form>
        </div>
        <div id="cavil-pkg-search" class="col-sm-12 col-md-4">
          <form @submit.prevent="searchNow" class="form-inline">
            <label class="col-form-label" for="inlineSearch">Filter:&nbsp;</label>
            <input v-model="search" type="text" class="form-control" id="inlineSearch" />
          </form>
        </div>
      </div>
      <div class="row">
        <div class="col-12">
          <table class="table table-striped table-bordered">
            <thead>
              <tr>
                <th class="link" style="width: 50%">License</th>
                <th>SPDX</th>
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
        <div class="col-6">
          <ShownEntries :end.sync="end" :start.sync="start" :total.sync="total" />
        </div>
        <div class="col-6" id="cavil-pagination">
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
import Refresh from './mixins/refresh.js';

export default {
  name: 'KnownLicenses',
  mixins: [Refresh],
  components: {PaginationLinks, ShownEntries},
  data() {
    return {
      end: 0,
      licenses: null,
      params: {limit: 10, offset: 0, search: ''},
      refreshUrl: '/pagination/licenses/known',
      search: '',
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
          spdx: license.spdx
        });
      }
      this.licenses = licenses;
    },
    searchNow() {
      this.cancelApiRefresh();
      this.licenses = null;
      this.doApiRefresh();
    }
  },
  watch: {
    search: function (val) {
      this.params.search = val;
      this.params.offset = 0;
    }
  }
};
</script>

<style>
.table {
  margin-top: 1rem;
}
#cavil-pkg-search form {
  margin: 2px 0;
  white-space: nowrap;
  justify-content: flex-end;
}
#all-done {
  text-align: center;
}
</style>
