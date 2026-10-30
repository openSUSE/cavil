<template>
  <CavilListLayout
    :current-page="currentPage"
    :end="end"
    :filter="filter"
    filter-aria-label="Audit log filters"
    filter-input-id="audit-log-filter-input"
    filter-label="Filter by name or id"
    filter-placeholder="Filter by name or id"
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
        <span>Show</span>
        <select v-model="params.category" @change="gotoPage(1)" class="form-select" id="audit-log-category">
          <option value="">All events</option>
          <option value="reviews">Reviews</option>
          <option value="limitations">Limitations</option>
          <option value="patterns">Patterns</option>
          <option value="ignored">Ignored</option>
          <option value="settings">Settings</option>
        </select>
      </label>
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
          <th>Name</th>
          <th>Subject</th>
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
            <template v-if="event.subject">
              <a v-if="event.subject.href" :href="event.subject.href">{{ event.subject.text }}</a>
              <span v-else :class="{'cavil-list-token': event.subject.mono}" :title="event.subject.title">{{
                event.subject.text
              }}</span>
              <span v-if="event.subject.note" class="text-muted">{{ event.subject.note }}</span>
            </template>
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
import {riskName} from './helpers/riskLevels.js';
import Refresh from './mixins/refresh.js';
import moment from 'moment';

const clip = text => (text.length > 300 ? `${text.slice(0, 300)}…` : text);
const lines = (...parts) => parts.filter(part => part != null && part !== '').join('\n');
const count = n => `${n} ${n === 1 ? 'pattern' : 'patterns'}`;
const proposedBy = data => (data.contributor ? `Proposed by ${data.contributor}` : null);
const pattern = data =>
  lines(`${data.license || 'Keyword pattern'}, risk ${data.risk}`, proposedBy(data), clip(data.text));
const patternLink = data => ({text: `Pattern ${data.pattern}`, href: `/licenses/edit_pattern/${data.pattern}`});
const changes = data =>
  lines(
    ...Object.keys(data.changes)
      .sort()
      .map(field => {
        const [from, to] = data.changes[field];
        if (field === 'text') return `text:\n${clip(to)}`;
        return `${field}: ${from === '' ? '(none)' : (from ?? 'mixed')} → ${to === '' ? '(none)' : to}`;
      })
  );
const settingLabels = {
  auto_accept_risk: 'Accept low-risk packages nobody has reviewed yet',
  acceptable_risk: 'Accept packages a person has reviewed before',
  acceptable_packages: 'Always accept these packages',
  sbom_creator_name: 'SBOM organisation',
  sbom_creator_email: 'SBOM email address',
  sbom_creator_url: 'SBOM web address'
};
const settingValue = (field, value) => {
  if (Array.isArray(value)) return value.length ? value.join(', ') : '(none)';
  if (field === 'auto_accept_risk' && value === 0) return 'off';
  if (value === '') return '(none)';
  return typeof value === 'number' ? `${value} - ${riskName(value)}` : String(value);
};
const settingChanges = data =>
  lines(
    ...[...new Set([...Object.keys(data.changes), ...(data.reset ?? [])])].sort().map(field => {
      const label = settingLabels[field] ?? field;
      if (!data.changes[field]) return `${label}: back to default`;
      const [from, to] = data.changes[field];
      const reset = data.reset?.includes(field) ? ' (default)' : '';
      return `${label}: ${settingValue(field, from)} → ${settingValue(field, to)}${reset}`;
    })
  );
const exclusion = data => ({text: `${data.package_glob} : ${data.file}`, mono: true});

// Unknown types still render, so a new event type is visible before it gets a formatter here
const formatters = {
  'review.decision': (data, event) => ({
    summary: data.from === data.to ? `${data.to} (decided again)` : `${data.from} → ${data.to}`,
    detail: data.result,
    subject: {
      text: data.checksum ?? event.package,
      href: `/reviews/details/${event.package}`,
      note: data.checksum != null && data.checksum !== event.package_checksum ? ' (changed)' : null
    }
  }),
  'limitation.added': data => ({summary: 'Limitation added', detail: data.to}),
  'limitation.edited': data => ({summary: 'Limitation edited', detail: data.to}),
  'limitation.removed': data => ({summary: 'Limitation removed', detail: data.from}),
  'pattern.created': data => ({summary: 'Pattern created', detail: pattern(data), subject: patternLink(data)}),
  'pattern.updated': data => ({summary: 'Pattern edited', detail: changes(data), subject: patternLink(data)}),
  'pattern.removed': data => ({
    summary: 'Pattern removed',
    detail: pattern(data),
    subject: {text: `Pattern ${data.pattern}`}
  }),
  'license.updated': data => {
    const name = data.changes.license?.[1] ?? data.license;
    return {
      summary: `License edited (${count(data.patterns)})`,
      detail: lines(
        changes(data),
        data.merged
          ? `merged with ${count(data.merged.patterns)} already there${
              data.merged.spdx
                ? `, their spdx: ${data.merged.spdx[0] || '(none)'} → ${data.merged.spdx[1] || '(none)'}`
                : ''
            }`
          : null
      ),
      subject: {text: name, href: `/licenses/${encodeURIComponent(name)}`}
    };
  },
  'ignored_match.added': data => ({
    summary: 'Match ignored',
    detail: proposedBy(data),
    subject: {text: data.hash.slice(0, 12), title: data.hash, mono: true}
  }),
  'ignored_match.removed': data => ({
    summary: 'Ignored match removed',
    subject: {text: data.hash.slice(0, 12), title: data.hash, mono: true}
  }),
  'snippet.non_license': data => ({
    summary: 'Marked as not legal text',
    detail: proposedBy(data),
    subject: {text: data.hash.slice(0, 12), title: data.hash, mono: true}
  }),
  'ignored_file.added': data => ({
    summary: 'Files ignored',
    detail: proposedBy(data),
    subject: {text: data.glob, mono: true}
  }),
  'ignored_file.removed': data => ({summary: 'Ignored files removed', subject: {text: data.glob, mono: true}}),
  'settings.changed': data => ({summary: 'Settings changed', detail: settingChanges(data)}),
  'bot_token.added': data => ({summary: 'Bot token added', detail: data.description}),
  'bot_token.removed': data => ({summary: 'Bot token removed', detail: data.description}),
  'unpack_exclusion.added': data => ({summary: 'Excluded file added', detail: data.reason, subject: exclusion(data)}),
  'unpack_exclusion.removed': data => ({
    summary: 'Excluded file removed',
    detail: data.reason,
    subject: exclusion(data)
  })
};
const fallback = (data, event) => ({summary: event.type, detail: JSON.stringify(data)});

export default {
  name: 'AuditLog',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, LegalLoading},
  data() {
    const params = getParams({limit: 25, offset: 0, byUser: false, category: '', filter: ''});

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
        const login = event.login ?? 'Cavil';
        return {
          id: event.id,
          time: created.format('YYYY-MM-DD HH:mm:ss Z'),
          ago: created.fromNow(),
          packageName: event.package_name,
          actor: event.data.ai_assisted ? `${login} (AI assistant)` : login,
          ...(formatters[event.type] ?? fallback)(event.data, event)
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
    ...genParamWatchers('limit', 'offset', 'byUser', 'category'),
    filter: function (val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>
