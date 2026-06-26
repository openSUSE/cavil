<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    filter-aria-label="Recent review filters"
    filter-input-id="recent-reviews-filter-input"
    filter-label="Filter reviews"
    filter-placeholder="Filter reviews"
    plural="recent reviews"
    singular="recent review"
    :start="start"
    :total="total"
    :total-pages="totalPages"
    @filter-submit="filterNow"
    @goto-page="gotoPage"
    @update:filter="filter = $event"
  >
    <template #controls>
      <button
        id="cavil-pkg-by-user"
        @click="toggleFilter('byUser')"
        :aria-pressed="params.byUser.toString()"
        :class="{'is-active': params.byUser}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.byUser" class="fa-solid fa-check" aria-hidden="true"></i>
        Reviewed by user
      </button>
      <button
        id="cavil-pkg-ai-assisted"
        @click="toggleFilter('aiAssisted')"
        :aria-pressed="params.aiAssisted.toString()"
        :class="{'is-active': params.aiAssisted}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.aiAssisted" class="fa-solid fa-check" aria-hidden="true"></i>
        Reviewed with AI
      </button>
      <button
        id="cavil-pkg-unresolved-matches"
        @click="toggleFilter('unresolvedMatches')"
        :aria-pressed="params.unresolvedMatches.toString()"
        :class="{'is-active': params.unresolvedMatches}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.unresolvedMatches" class="fa-solid fa-check" aria-hidden="true"></i>
        Unresolved matches
      </button>
    </template>

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
          <th class="priority">Priority</th>
          <th class="link">Link</th>
          <th class="created">Created</th>
          <th class="reviewed">Reviewed</th>
          <th class="package">Package</th>
          <th class="state">State</th>
          <th class="result">Comment</th>
          <th class="login">Reviewing User</th>
          <th class="report">Report</th>
        </tr>
      </thead>
      <tbody v-if="reviews === null">
        <tr>
          <td id="all-done" colspan="9" class="cavil-list-state">
            <i class="fa-solid fa-rotate fa-spin"></i> Loading reviews...
          </td>
        </tr>
      </tbody>
      <tbody v-else-if="reviews.length > 0">
        <tr v-for="review in reviews" :key="review.id">
          <td class="cavil-list-priority"><PriorityBadge :priority.sync="review.priority" /></td>
          <td class="cavil-list-link" v-html="review.link"></td>
          <td class="relative-time cavil-list-time">{{ review.created }}</td>
          <td class="relative-time cavil-list-time">{{ review.reviewed }}</td>
          <td class="cavil-list-package" v-html="review.package"></td>
          <td v-html="review.state"></td>
          <td class="cavil-list-comment">
            <div class="cavil-list-comment-body" v-html="review.result"></div>
          </td>
          <td v-html="review.login"></td>
          <td class="cavil-list-report" v-html="review.report"></td>
        </tr>
      </tbody>
      <tbody v-else>
        <tr>
          <td id="all-done" colspan="9" class="cavil-list-empty-cell">
            <EmptyState message="No recent reviews found." />
          </td>
        </tr>
      </tbody>
    </table>
  </CavilListLayout>
</template>

<script>
import CavilListLayout from './components/CavilListLayout.vue';
import EmptyState from './components/EmptyState.vue';
import PriorityBadge from './components/PriorityBadge.vue';
import {externalLink, packageLink, reportLink, setupPopoverDelayed} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'RecentReviews',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, PriorityBadge},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      byUser: false,
      aiAssisted: false,
      unresolvedMatches: false,
      filter: ''
    });

    return {
      end: 0,
      params,
      reviews: null,
      refreshUrl: '/pagination/reviews/recent',
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
    gotoPage(num) {
      this.cancelApiRefresh();
      const limit = this.params.limit;
      this.params.offset = num * limit - limit;
      this.reviews = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      const reviews = [];
      for (const review of data.page) {
        const login = [];
        if (review.login) {
          login.push(review.login);
          if (review.ai_assisted) login.push('<i class="fa-solid fa-robot"></i>');
        }

        reviews.push({
          link: externalLink(review),
          created: moment(review.created_epoch * 1000).fromNow(),
          reviewed: moment(review.reviewed_epoch * 1000).fromNow(),
          package: packageLink(review),
          priority: review.priority,
          report: reportLink(review),
          login: login.join(' '),
          result: review.result,
          state: review.state
        });
      }
      this.reviews = reviews;
      setupPopoverDelayed();
    },
    toggleFilter(name) {
      this.params[name] = !this.params[name];
      this.gotoPage(1);
    },
    filterNow() {
      this.cancelApiRefresh();
      this.reviews = null;
      this.doApiRefresh();
    }
  },
  watch: {
    ...genParamWatchers('limit', 'offset', 'byUser', 'aiAssisted', 'unresolvedMatches'),
    filter: function (val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>
