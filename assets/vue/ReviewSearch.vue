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
            <div class="form-check mb-2 mr-sm-2">
              <input
                v-model="params.notObsolete"
                @change="gotoPage(1)"
                type="checkbox"
                class="form-check form-check-inline"
                id="cavil-search-not-obsolete"
              />
              <label for="cavil-search-not-obsolete">Not Obsolete</label>
            </div>
          </form>
        </div>
        <div id="cavil-pkg-filter" class="col-sm-12 col-md-4">
          <form @submit.prevent="filterNow" class="form-inline">
            <label class="col-form-label" for="inlineFilter">Filter:&nbsp;</label>
            <input v-model="filter" type="text" class="form-control" id="inlineFilter" />
          </form>
        </div>
      </div>
      <div class="row">
        <div class="col-12">
          <table class="table table-striped table-bordered">
            <thead>
              <tr>
                <th class="created">Created</th>
                <th class="state">State</th>
                <th class="comment">Comment</th>
                <th class="user">Reviewing User</th>
                <th class="report">Report</th>
              </tr>
            </thead>
            <tbody v-if="reviews === null">
              <tr>
                <td id="all-done" colspan="5"><i class="fas fa-sync fa-spin"></i> Loading reviews...</td>
              </tr>
            </tbody>
            <tbody v-else-if="reviews.length > 0">
              <tr v-for="review in reviews" :key="review.id">
                <td class="timeago">{{ review.created }}</td>
                <td v-html="review.state"></td>
                <td v-html="review.comment"></td>
                <td v-html="review.user"></td>
                <td v-html="review.report"></td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr>
                <td id="all-done" colspan="5">No reviews found.</td>
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
import {reportLink} from './helpers/links.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

export default {
  name: 'ReviewSearch',
  mixins: [Refresh],
  components: {PaginationLinks, ShownEntries},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      notObsolete: false,
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
          created: moment(review.created_epoch * 1000).fromNow(),
          report: reportLink(review),
          state: review.state,
          user: review.user
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
    ...genParamWatchers('limit', 'offset', 'notObsolete'),
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
