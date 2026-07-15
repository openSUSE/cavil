<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    count-icon="fa-solid fa-box-open"
    filter-aria-label="Package review filters"
    filter-input-id="product-reviews-filter-input"
    filter-label="Filter packages"
    filter-placeholder="Filter packages"
    :page-title="currentProduct"
    plural="packages"
    singular="package"
    :start="start"
    :total="total"
    :total-pages="totalPages"
    @filter-submit="filterNow"
    @goto-page="gotoPage"
    @update:filter="filter = $event"
  >
    <template #controls>
      <button
        id="cavil-pkg-attention"
        @click="toggleFilter('attention')"
        :aria-pressed="params.attention.toString()"
        :class="{'is-active': params.attention}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.attention" class="fa-solid fa-check" aria-hidden="true"></i>
        Needs attention
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
      <button
        id="cavil-pkg-patent"
        @click="toggleFilter('patent')"
        :aria-pressed="params.patent.toString()"
        :class="{'is-active': params.patent}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.patent" class="fa-solid fa-check" aria-hidden="true"></i>
        Patent
      </button>
      <button
        id="cavil-pkg-trademark"
        @click="toggleFilter('trademark')"
        :aria-pressed="params.trademark.toString()"
        :class="{'is-active': params.trademark}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.trademark" class="fa-solid fa-check" aria-hidden="true"></i>
        Trademark
      </button>
      <button
        id="cavil-pkg-cla"
        @click="toggleFilter('cla')"
        :aria-pressed="params.cla.toString()"
        :class="{'is-active': params.cla}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.cla" class="fa-solid fa-check" aria-hidden="true"></i>
        CLA
      </button>
      <button
        id="cavil-pkg-eula"
        @click="toggleFilter('eula')"
        :aria-pressed="params.eula.toString()"
        :class="{'is-active': params.eula}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.eula" class="fa-solid fa-check" aria-hidden="true"></i>
        EULA
      </button>
      <button
        id="cavil-pkg-export-restricted"
        @click="toggleFilter('exportRestricted')"
        :aria-pressed="params.exportRestricted.toString()"
        :class="{'is-active': params.exportRestricted}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.exportRestricted" class="fa-solid fa-check" aria-hidden="true"></i>
        Export restricted
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
          <th class="package">Package</th>
          <th class="state">State</th>
          <th class="report">Report</th>
        </tr>
      </thead>
      <tbody v-if="reviews === null">
        <tr>
          <td id="all-done" colspan="3" class="cavil-list-state">
            <LegalLoading message="Loading review docket..." size="small" />
          </td>
        </tr>
      </tbody>
      <tbody v-else-if="reviews.length > 0">
        <tr v-for="review in reviews" :key="review.id">
          <td class="cavil-list-package" v-html="review.package"></td>
          <td v-html="review.state"></td>
          <td class="cavil-list-report" v-html="review.report"></td>
        </tr>
      </tbody>
      <tbody v-else>
        <tr>
          <td id="all-done" colspan="3" class="cavil-list-empty-cell">
            <EmptyState message="No package reviews found." />
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
import {packageLink, reportLink, setupPopoverDelayed} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';

export default {
  name: 'ProductReviews',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, LegalLoading},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      attention: false,
      unresolvedMatches: false,
      patent: false,
      trademark: false,
      exportRestricted: false,
      cla: false,
      eula: false,
      filter: ''
    });

    return {
      end: 0,
      params,
      reviews: null,
      refreshUrl: `/pagination/products/${this.currentProduct}`,
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
          package: packageLink(review),
          report: reportLink(review),
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
    ...genParamWatchers(
      'limit',
      'offset',
      'attention',
      'unresolvedMatches',
      'patent',
      'trademark',
      'exportRestricted',
      'cla',
      'eula'
    ),
    filter: function (val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>
