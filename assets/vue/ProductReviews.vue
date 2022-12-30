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
            <label class="col-form-label" for="inlineSearch">Search:&nbsp;</label>
            <input v-model="search" type="text" class="form-control" id="inlineSearch" />
          </form>
        </div>
      </div>
      <div class="row">
        <div class="col-12">
          <table class="table table-striped table-bordered">
            <thead>
              <tr>
                <th class="package">Package</th>
                <th class="state">State</th>
                <th class="report">Report</th>
              </tr>
            </thead>
            <tbody v-if="reviews === null">
              <tr>
                <td id="all-done" colspan="3"><i class="fas fa-sync fa-spin"></i> Loading reviews...</td>
              </tr>
            </tbody>
            <tbody v-else-if="reviews.length > 0">
              <tr v-for="review in reviews" :key="review.id">
                <td v-html="review.package"></td>
                <td v-html="review.state"></td>
                <td v-html="review.report"></td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr>
                <td id="all-done" colspan="3">No reviews found.</td>
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
import {packageLink, reportLink} from './helpers/links.js';
import Refresh from './mixins/refresh.js';

export default {
  name: 'ProductReviews',
  mixins: [Refresh],
  components: {PaginationLinks, ShownEntries},
  data() {
    return {
      end: 0,
      params: {limit: 10, offset: 0, search: ''},
      reviews: null,
      refreshUrl: `/pagination/products/${this.currentProduct}`,
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
    },
    searchNow() {
      this.cancelApiRefresh();
      this.reviews = null;
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
