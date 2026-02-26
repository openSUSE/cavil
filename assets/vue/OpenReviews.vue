<template>
  <div class="mt-3">
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
          <div class="col-lg-2">
            <div class="form-floating">
              <select v-model="params.priority" @change="gotoPage(1)" class="form-control cavil-pkg-priority">
                <option>1</option>
                <option>2</option>
                <option>3</option>
                <option>4</option>
                <option>5</option>
                <option>6</option>
                <option>7</option>
                <option>8</option>
              </select>
              <label class="form-label">Minimum Priority</label>
            </div>
          </div>
          <div class="col">
            <div class="form-check">
              <input
                v-model="params.inProgress"
                @change="gotoPage(1)"
                class="form-check-input"
                type="checkbox"
                id="cavil-pkg-in-progress"
              />
              <label class="form-check-label" for="cavil-pkg-in-progress"> In Progress </label>
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
                <th class="package">Package</th>
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
                <td class="text-center"><PriorityBadge :priority.sync="review.priority" /></td>
                <td v-html="review.link"></td>
                <td class="timeago">{{ review.created }}</td>
                <td v-html="review.package"></td>
                <td v-html="review.report"></td>
              </tr>
            </tbody>
            <tbody v-else>
              <tr>
                <td id="all-done" colspan="5">All reviews are done!</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <div class="row">
        <div class="col-lg-6 mb-4">
          <ShownEntries :end.sync="end" :start.sync="start" :total.sync="total" />
        </div>
        <div class="col-lg-6 mb-4" id="cavil-pagination">
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
import {externalLink, packageLink, reportLink, setupPopoverDelayed} from './helpers/links.js';
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
          link: externalLink(review),
          created: moment(review.created_epoch * 1000).fromNow(),
          package: packageLink(review),
          priority: review.priority,
          report: reportLink(review)
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
    ...genParamWatchers('limit', 'offset', 'inProgress', 'priority'),
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
