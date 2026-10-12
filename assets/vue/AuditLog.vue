<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    filter-aria-label="Audit log filters"
    filter-input-id="audit-log-filter-input"
    filter-label="Filter by package name or id"
    filter-placeholder="Filter by package name or id"
    plural="events"
    singular="event"
    :start="start"
    :total="total"
    :total-pages="totalPages"
    @filter-submit="filterNow"
    @goto-page="gotoPage"
    @update:filter="filter = $event"
  >
    <template #controls>
      <button
        id="audit-log-by-user"
        @click="toggleFilter('byUser')"
        :aria-pressed="params.byUser.toString()"
        :class="{'is-active': params.byUser}"
        type="button"
        class="cavil-list-toggle"
      >
        <i v-if="params.byUser" class="fa-solid fa-check" aria-hidden="true"></i>
        By user
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

    <table class="cavil-list-table cavil-review-docket-table table">
      <thead>
        <tr>
          <th>Time</th>
          <th>Package</th>
          <th>Report</th>
          <th>Event</th>
          <th>By</th>
        </tr>
      </thead>
      <tbody v-if="events === null">
        <tr>
          <td colspan="5" class="cavil-list-state">
            <LegalLoading message="Loading audit log..." size="small" />
          </td>
        </tr>
      </tbody>
      <tbody v-else-if="events.length > 0">
        <tr v-for="event in events" :key="event.id">
          <td class="cavil-list-time" :title="event.ago">{{ event.time }}</td>
          <td class="cavil-list-package">
            <a v-if="event.packageName" :href="`/search?q=${encodeURIComponent(event.packageName)}`">{{
              event.packageName
            }}</a>
          </td>
          <td class="cavil-list-report">
            <a v-if="event.package" :href="`/reviews/details/${event.package}`">{{
              event.checksum ?? event.package
            }}</a>
            <span v-if="event.changed" class="text-muted" title="The report has changed since"> (changed) </span>
          </td>
          <td>
            <div>{{ event.summary }}</div>
            <div v-if="event.detail" class="cavil-list-comment-body">{{ event.detail }}</div>
          </td>
          <td>{{ event.actor }}</td>
        </tr>
      </tbody>
      <tbody v-else>
        <tr>
          <td colspan="5" class="cavil-list-empty-cell">
            <EmptyState message="No audit events." />
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
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

// Unknown types still render, so a new event type is visible before it gets a formatter here
const formatters = {
  'review.decision': data => ({
    summary: data.from === data.to ? `${data.to} (decided again)` : `${data.from} → ${data.to}`,
    detail: data.result
  }),
  'limitation.added': data => ({summary: 'Limitation added', detail: data.to}),
  'limitation.edited': data => ({summary: 'Limitation edited', detail: data.to}),
  'limitation.removed': data => ({summary: 'Limitation removed', detail: data.from})
};
const fallback = (data, type) => ({summary: type, detail: JSON.stringify(data)});

export default {
  name: 'AuditLog',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, LegalLoading},
  data() {
    const params = getParams({limit: 25, offset: 0, byUser: false, filter: ''});

    return {
      end: 0,
      events: null,
      params,
      refreshDelay: 0,
      refreshUrl: '/pagination/audit',
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
      this.events = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      this.events = data.page.map(event => {
        const created = moment(event.created_epoch * 1000);
        const checksum = event.data.checksum;
        const login = event.login ?? 'Cavil';
        return {
          id: event.id,
          time: created.format('YYYY-MM-DD HH:mm:ss Z'),
          ago: created.fromNow(),
          package: event.package,
          packageName: event.package_name,
          checksum,
          changed: checksum != null && checksum !== event.package_checksum,
          actor: event.data.ai_assisted ? `${login} (AI assistant)` : login,
          ...(formatters[event.type] ?? fallback)(event.data, event.type)
        };
      });
    },
    toggleFilter(name) {
      this.params[name] = !this.params[name];
      this.gotoPage(1);
    },
    filterNow() {
      this.cancelApiRefresh();
      this.events = null;
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
