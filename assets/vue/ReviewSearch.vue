<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    count-icon="fa-solid fa-magnifying-glass"
    filter-aria-label="Search result filters"
    filter-input-id="review-search-filter-input"
    filter-label="Filter search results"
    filter-placeholder="Filter search results"
    page-title="Search Results"
    plural="search results"
    singular="search result"
    :start="start"
    :total="total"
    :total-pages="totalPages"
    @filter-submit="filterNow"
    @goto-page="gotoPage"
    @update:filter="filter = $event"
  >
    <template #controls>
      <button
        id="cavil-search-not-obsolete"
        @click="toggleFilter('notObsolete')"
        :aria-pressed="params.notObsolete.toString()"
        :class="{'is-active': params.notObsolete}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.notObsolete" class="fa-solid fa-check" aria-hidden="true"></i>
        Not obsolete
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
          <th class="imported">Imported</th>
          <th class="state">State</th>
          <th class="comment">Comment</th>
          <th class="user">Reviewing User</th>
          <th class="created">Package</th>
          <th class="report">Report</th>
        </tr>
      </thead>
      <tbody v-if="reviews === null">
        <tr>
          <td id="all-done" colspan="6" class="cavil-list-state">
            <LegalLoading message="Searching review docket..." size="small" />
          </td>
        </tr>
      </tbody>
      <tbody v-else-if="reviews.length > 0">
        <tr v-for="review in reviews" :key="review.id">
          <td class="relative-time cavil-list-time">{{ review.imported }}</td>
          <td v-html="review.state"></td>
          <td class="cavil-list-comment">
            <div class="cavil-list-comment-body" v-html="review.comment"></div>
          </td>
          <td v-html="review.user"></td>
          <td class="cavil-list-package" v-html="review.package"></td>
          <td class="cavil-list-report" v-html="review.report"></td>
        </tr>
      </tbody>
      <tbody v-else>
        <tr>
          <td id="all-done" colspan="6" class="cavil-list-empty-cell">
            <EmptyState message="No reviews found." />
          </td>
        </tr>
      </tbody>
    </table>
  </CavilListLayout>
</template>

<script>
import CavilListLayout from './components/CavilListLayout.vue';
import EmptyState from './components/EmptyState.vue';
import LegalLoading from './components/LegalLoading.vue';
import {reportLink, setupPopoverDelayed} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'ReviewSearch',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, LegalLoading},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      notObsolete: true,
      filter: ''
    });

    return {
      end: 0,
      params,
      reviews: null,
      refreshUrl: `/pagination/search/${this.currentPackage}`,
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
        reviews.push({
          comment: review.comment,
          imported: moment(review.imported_epoch * 1000).fromNow(),
          package: review.package,
          report: reportLink(review),
          state: review.state,
          user: review.user
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
    ...genParamWatchers('limit', 'offset', 'notObsolete'),
    filter: function (val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>
