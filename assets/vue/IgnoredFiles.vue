<template>
  <div>
    <div class="row">
      <div class="col-12 alert alert-primary" role="alert">
        These globs are used to decide which files the indexer should ignore when scanning for license pattern matches.
      </div>
    </div>
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
              <label class="form-label">Globs per Page</label>
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
                <th>Glob</th>
                <th>Created</th>
                <th>Owner</th>
                <th></th>
              </tr>
            </thead>
            <tbody v-if="globs === null">
              <tr>
                <td id="all-done" colspan="4"><i class="fas fa-sync fa-spin"></i> Loading globs...</td>
              </tr>
            </tbody>
            <tbody v-else-if="globs.length > 0">
              <tr v-for="glob in globs" :key="glob.id">
                <td>{{ glob.glob }}</td>
                <td>{{ glob.created }}</td>
                <td>{{ glob.login }}</td>
                <td class="text-center">
                  <span class="cavil-action text-center">
                    <a @click="deleteGlob(glob)" href="#"><i class="fas fa-trash"></i></a>
                  </span>
                </td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr>
                <td id="all-done" colspan="4">No globs found.</td>
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
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'IgnoredFiles',
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
      globs: null,
      params,
      refreshUrl: '/pagination/files/ignored',
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
    async deleteGlob(glob) {
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(glob.removeUrl, {query: {_method: 'DELETE'}});
      this.doApiRefresh();
    },
    gotoPage(num) {
      this.cancelApiRefresh();
      const limit = this.params.limit;
      this.params.offset = num * limit - limit;
      this.globs = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      const globs = [];
      for (const glob of data.page) {
        globs.push({
          id: glob.id,
          glob: glob.glob,
          created: moment(glob.created_epoch * 1000).fromNow(),
          login: glob.login,
          removeUrl: `/ignored-files/${glob.id}`
        });
      }
      this.globs = globs;
    },
    filterNow() {
      this.cancelApiRefresh();
      this.globs = null;
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
.cavil-action a {
  color: #212529;
  text-decoration: none;
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
