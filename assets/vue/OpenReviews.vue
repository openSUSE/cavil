<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    filter-aria-label="Open review filters"
    filter-input-id="open-reviews-filter-input"
    filter-label="Filter reviews"
    filter-placeholder="Filter reviews"
    plural="open reviews"
    singular="open review"
    :start="start"
    :total="total"
    :total-pages="totalPages"
    @filter-submit="filterNow"
    @goto-page="gotoPage"
    @update:filter="filter = $event"
  >
    <template #controls>
      <button
        id="cavil-pkg-in-progress"
        @click="toggleFilter('inProgress')"
        :aria-pressed="params.inProgress.toString()"
        :class="{'is-active': params.inProgress}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.inProgress" class="fa-solid fa-check" aria-hidden="true"></i>
        In progress
      </button>
      <label class="cavil-list-control">
        <span>Minimum priority</span>
        <select v-model="params.priority" @change="gotoPage(1)" class="form-select cavil-pkg-priority">
          <option>1</option>
          <option>2</option>
          <option>3</option>
          <option>4</option>
          <option>5</option>
          <option>6</option>
          <option>7</option>
          <option>8</option>
        </select>
      </label>
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
          <th class="imported">Imported</th>
          <th class="package">Package</th>
          <th class="report">Report</th>
        </tr>
      </thead>
      <tbody v-if="reviews === null">
        <tr>
          <td id="all-done" colspan="5" class="cavil-list-state">
            <i class="fa-solid fa-rotate fa-spin"></i> Loading reviews...
          </td>
        </tr>
      </tbody>
      <tbody v-else-if="reviews.length > 0">
        <tr v-for="review in reviews" :key="review.id">
          <td class="cavil-list-priority"><PriorityBadge :priority.sync="review.priority" /></td>
          <td class="cavil-list-link" v-html="review.link"></td>
          <td class="relative-time cavil-list-time">{{ review.imported }}</td>
          <td class="cavil-list-package" v-html="review.package"></td>
          <td class="cavil-list-report" v-html="review.report"></td>
        </tr>
      </tbody>
      <tbody v-else>
        <tr>
          <td id="all-done" colspan="5" class="cavil-list-empty-cell">
            <EmptyState message="No open reviews remain. Nice work keeping the queue clear." />
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
  name: 'OpenReviews',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, PriorityBadge},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      inProgress: false,
      priority: 1,
      filter: ''
    });

    return {
      end: 0,
      params,
      reviews: null,
      refreshUrl: '/pagination/reviews/open',
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
          id: review.id,
          link: externalLink(review),
          imported: moment(review.imported_epoch * 1000).fromNow(),
          package: packageLink(review),
          priority: review.priority,
          report: reportLink(review)
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
    ...genParamWatchers('limit', 'offset', 'inProgress', 'priority'),
    filter: function (val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>
