<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    filter-aria-label="Ephemeral review filters"
    filter-input-id="ephemeral-reviews-filter-input"
    filter-label="Filter reviews"
    filter-placeholder="Filter reviews"
    plural="ephemeral reviews"
    singular="ephemeral review"
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
          <th class="priority">Priority</th>
          <th class="link">Link</th>
          <th class="package">Package</th>
          <th class="login">Uploaded By</th>
          <th class="imported">Uploaded</th>
          <th class="reviewed">Deletes</th>
          <th class="state">State</th>
          <th class="report">Report</th>
        </tr>
      </thead>
      <tbody v-if="reviews === null">
        <tr>
          <td id="all-done" colspan="8" class="cavil-list-state">
            <LegalLoading message="Loading ephemeral reviews..." size="small" />
          </td>
        </tr>
      </tbody>
      <tbody v-else-if="reviews.length > 0">
        <tr v-for="review in reviews" :key="review.id">
          <td class="cavil-list-priority"><PriorityBadge :priority.sync="review.priority" /></td>
          <td class="cavil-list-link"><ExternalLink :link="review.externalLink" /></td>
          <td class="cavil-list-package" v-html="review.package"></td>
          <td v-html="review.login"></td>
          <td class="relative-time cavil-list-time">{{ review.uploaded }}</td>
          <td class="relative-time cavil-list-time">{{ review.deletes }}</td>
          <td v-html="review.state"></td>
          <td class="cavil-list-report" v-html="review.report"></td>
        </tr>
      </tbody>
      <tbody v-else>
        <tr>
          <td id="all-done" colspan="8" class="cavil-list-empty-cell">
            <EmptyState message="No active ephemeral reviews." />
          </td>
        </tr>
      </tbody>
    </table>
  </CavilListLayout>
</template>

<script>
import CavilListLayout from './components/CavilListLayout.vue';
import EmptyState from './components/EmptyState.vue';
import ExternalLink from './components/ExternalLink.vue';
import LegalLoading from './components/LegalLoading.vue';
import PriorityBadge from './components/PriorityBadge.vue';
import {packageLink, reportLink, setupPopoverDelayed} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'EphemeralReviews',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, ExternalLink, LegalLoading, PriorityBadge},
  data() {
    const params = getParams({limit: 10, offset: 0, filter: ''});

    return {
      end: 0,
      params,
      reviews: null,
      refreshUrl: '/pagination/reviews/ephemeral',
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
          externalLink: review.external_link_data ?? review.external_link,
          uploaded: review.created_epoch ? moment(review.created_epoch * 1000).fromNow() : '',
          deletes: review.ephemeral_delete ? moment(review.ephemeral_delete * 1000).fromNow() : '',
          package: packageLink(review),
          priority: review.priority,
          report: reportLink(review),
          login: review.login ?? '',
          state: review.state
        });
      }
      this.reviews = reviews;
      setupPopoverDelayed();
    },
    filterNow() {
      this.cancelApiRefresh();
      this.reviews = null;
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
