<template>
  <div>
    <div class="row">
      <div class="col-12 alert alert-primary" role="alert">
        These ignored matches are used to decide which snippets the indexer should ignore when scanning for new keyword
        matches.
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
              <label class="form-label">Matches per Page</label>
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
                <th>Ignored Match</th>
                <th>Package</th>
                <th>Created</th>
                <th>Contributor</th>
                <th>Owner</th>
                <th></th>
              </tr>
            </thead>
            <tbody v-if="matches === null">
              <tr>
                <td id="all-done" colspan="6"><i class="fas fa-sync fa-spin"></i> Loading ignored matches...</td>
              </tr>
            </tbody>
            <tbody v-else-if="matches.length > 0">
              <tr v-for="match in matches" :key="match.id">
                <td v-if="match.snippetUrl !== null">
                  <a :href="match.snippetUrl">{{ match.hash }}</a>
                </td>
                <td v-else>{{ match.hash }}</td>
                <td v-html="match.package"></td>
                <td>{{ match.created }}</td>
                <td>{{ match.contributor_login }}</td>
                <td>{{ match.owner_login }}</td>
                <td class="text-center">
                  <span class="cavil-action text-center">
                    <a @click="deleteMatch(match)" href="#"><i class="fas fa-trash"></i></a>
                  </span>
                </td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr>
                <td id="all-done" colspan="6">No ignored matches found.</td>
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
import {packageLink} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'IgnoredMatches',
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
      matches: null,
      params,
      refreshUrl: '/pagination/matches/ignored',
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
    async deleteMatch(match) {
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(match.removeUrl, {query: {_method: 'DELETE'}});
      this.doApiRefresh();
    },
    gotoPage(num) {
      this.cancelApiRefresh();
      const limit = this.params.limit;
      this.params.offset = num * limit - limit;
      this.matches = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      const matches = [];
      for (const match of data.page) {
        matches.push({
          id: match.id,
          hash: match.hash,
          package: packageLink({name: match.packname}),
          created: moment(match.created_epoch * 1000).fromNow(),
          contributor_login: match.contributor_login,
          owner_login: match.owner_login,
          removeUrl: `/ignored-matches/${match.id}`,
          snippetUrl: match.snippet === null ? null : `/snippet/edit/${match.snippet.id}`
        });
      }
      this.matches = matches;
    },
    filterNow() {
      this.cancelApiRefresh();
      this.matches = null;
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
