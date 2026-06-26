<template>
  <div>
    <div class="row mt-3">
      <cavil-notice-panel intro class="col-12">
        These ignored matches are snippets that contain enough legal text so they cannot be ignored by the machine
        learning model, but are not relevant enough to be turned into license patterns, or the relevant parts are
        already covered by overlapping pattern matches.
      </cavil-notice-panel>
    </div>
    <CavilListLayout
      :current-page="currentPage"
      :end="end"
      :filter="filter"
      count-icon="fa-solid fa-eye-slash"
      filter-aria-label="Ignored match filters"
      filter-input-id="ignored-matches-filter-input"
      filter-label="Filter ignored matches"
      filter-placeholder="Filter ignored matches"
      plural="ignored matches"
      singular="ignored match"
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
            <th>Snippet</th>
            <th>Package</th>
            <th>Matches</th>
            <th>Created</th>
            <th>Contributor</th>
            <th>Owner</th>
            <th></th>
          </tr>
        </thead>
        <tbody v-if="matches === null">
          <tr>
            <td id="all-done" colspan="7" class="cavil-list-state">
              <i class="fa-solid fa-rotate fa-spin"></i> Loading ignored matches...
            </td>
          </tr>
        </tbody>
        <tbody v-else-if="matches.length > 0">
          <tr v-for="match in matches" :key="match.id">
            <td v-if="match.snippetUrl !== null" class="cavil-list-link">
              <a :href="match.snippetUrl">{{ match.hash }}</a>
            </td>
            <td v-else>
              <span class="cavil-list-token">{{ match.hash }}</span>
            </td>
            <td class="cavil-list-package" v-html="match.package"></td>
            <td class="cavil-list-primary">
              <a :href="match.searchUrl">{{ match.matches }} matches in {{ match.packages }} packages</a>
            </td>
            <td class="relative-time cavil-list-time">{{ match.created }}</td>
            <td>{{ match.contributor_login }}</td>
            <td>{{ match.owner_login }}</td>
            <td class="text-center">
              <button
                @click="deleteMatch(match)"
                type="button"
                class="cavil-icon-action cavil-icon-action-danger"
                title="Delete ignored match"
                aria-label="Delete ignored match"
              >
                <i class="fa-solid fa-trash"></i>
              </button>
            </td>
          </tr>
        </tbody>
        <tbody v-else>
          <tr>
            <td id="all-done" colspan="7" class="cavil-list-empty-cell">
              <EmptyState message="No ignored matches found." />
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
import {packageLink} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'IgnoredMatches',
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
          matches: match.matches,
          packages: match.packages,
          created: moment(match.created_epoch * 1000).fromNow(),
          contributor_login: match.contributor_login,
          owner_login: match.owner_login,
          searchUrl: `/search?ignore=${match.id}`,
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
