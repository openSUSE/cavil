<template>
  <div>
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
              <label class="form-label">Reviews per Page</label>
            </div>
          </div>
          <div class="col">
            <div class="form-check">
              <input
                v-model="params.byUser"
                @change="gotoPage(1)"
                type="checkbox"
                class="form-check-input"
                id="cavil-pkg-by-user"
              />
              <label class="form-check-label" for="cavil-pkg-by-user">Reviewed By User</label>
            </div>
          </div>
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
                <td id="all-done" colspan="9"><i class="fas fa-sync fa-spin"></i> Loading reviews...</td>
              </tr>
            </tbody>
            <tbody v-else-if="reviews.length > 0">
              <tr v-for="review in reviews" :key="review.id">
                <td class="text-center"><PriorityBadge :priority.sync="review.priority" /></td>
                <td v-html="review.link"></td>
                <td class="timeago">{{ review.created }}</td>
                <td class="timeago">{{ review.reviewed }}</td>
                <td v-html="review.package"></td>
                <td v-html="review.state"></td>
                <td v-html="review.result"></td>
                <td v-html="review.login"></td>
                <td v-html="review.report"></td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr>
                <td id="all-done" colspan="9">No reviews found.</td>
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
import PriorityBadge from './components/PriorityBadge.vue';
import ShownEntries from './components/ShownEntries.vue';
import {externalLink, packageLink, reportLink} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'OpenReviews',
  mixins: [Refresh],
  components: {PaginationLinks, PriorityBadge, ShownEntries},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      byUser: false,
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
        reviews.push({
          link: externalLink(review),
          created: moment(review.created_epoch * 1000).fromNow(),
          reviewed: moment(review.reviewed_epoch * 1000).fromNow(),
          package: packageLink(review),
          priority: review.priority,
          report: reportLink(review),
          login: review.login,
          result: review.result,
          state: review.state
        });
      }
      this.reviews = reviews;
    },
    filterNow() {
      this.cancelApiRefresh();
      this.reviews = null;
      this.doApiRefresh();
    }
  },
  watch: {
    ...genParamWatchers('limit', 'offset', 'byUser'),
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
#cavil-pkg-filter form {
  margin: 2px 0;
  white-space: nowrap;
  justify-content: flex-end;
}
#all-done {
  text-align: center;
}
</style>
