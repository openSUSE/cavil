<template>
  <section>
    <div class="cavil-settings-header">
      <h3>Excluded files</h3>
      <p>
        Files Cavil skips when it unpacks a package. Use this for files that break unpacking, such as zip bombs or
        archives that never finish, and for huge files that are only noise.
      </p>
      <p>Changes apply the next time a package is unpacked, a reindex alone does not pick them up.</p>
    </div>

    <div class="cavil-settings-actions">
      <button type="button" class="btn btn-success" id="add-exclusion" @click="adding = !adding">Add exclusion</button>
    </div>
    <Transition name="cavil-reveal">
      <div v-if="adding" class="cavil-reveal">
        <form class="cavil-settings-inline-form" @submit.prevent="add()">
          <div>
            <label for="exclusion-package" class="form-label">Package</label>
            <input id="exclusion-package" v-model="rule.package_glob" class="form-control" placeholder="rust*" />
            <div class="form-text">Use * to match several packages.</div>
          </div>
          <div>
            <label for="exclusion-file" class="form-label">File</label>
            <input id="exclusion-file" v-model="rule.file" class="form-control" placeholder="zip-bomb.zip" />
            <div class="form-text">A name or pattern, matched in any folder of the package.</div>
          </div>
          <div class="cavil-settings-inline-form-wide">
            <label for="exclusion-reason" class="form-label">Reason</label>
            <input id="exclusion-reason" v-model="rule.reason" class="form-control" placeholder="Zip bomb" />
            <div class="form-text">Why it is excluded, so nobody has to guess later.</div>
          </div>
          <div class="cavil-settings-inline-form-buttons">
            <button type="button" class="btn btn-secondary" @click="adding = false">Cancel</button>
            <button type="submit" class="btn btn-success" id="save-exclusion" :disabled="!canAdd">Add</button>
          </div>
        </form>
      </div>
    </Transition>

    <CavilListLayout
      :current-page="currentPage"
      :end="end"
      :filter="filter"
      count-icon="fa-solid fa-file-circle-xmark"
      filter-aria-label="Excluded file filters"
      filter-input-id="excluded-files-filter-input"
      filter-label="Filter excluded files"
      filter-placeholder="Filter excluded files"
      plural="excluded files"
      singular="excluded file"
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
            <th>Package</th>
            <th>File</th>
            <th>Reason</th>
            <th>Added</th>
            <th></th>
          </tr>
        </thead>
        <tbody v-if="exclusions === null">
          <tr>
            <td colspan="5" class="cavil-list-state">
              <LegalLoading message="Loading excluded files..." size="small" />
            </td>
          </tr>
        </tbody>
        <tbody v-else-if="exclusions.length > 0">
          <tr v-for="exclusion in exclusions" :key="exclusion.id">
            <td>
              <span class="cavil-list-token">{{ exclusion.package_glob }}</span>
            </td>
            <td>
              <span class="cavil-list-token">{{ exclusion.file }}</span>
            </td>
            <td>{{ exclusion.reason }}</td>
            <td class="cavil-list-time">{{ exclusion.login }}, {{ exclusion.created }}</td>
            <td class="text-center">
              <button
                @click="remove(exclusion)"
                type="button"
                class="cavil-icon-action cavil-icon-action-danger"
                title="Remove excluded file"
                aria-label="Remove excluded file"
              >
                <i class="fa-solid fa-trash"></i>
              </button>
            </td>
          </tr>
        </tbody>
        <tbody v-else>
          <tr>
            <td colspan="5" class="cavil-list-empty-cell">
              <EmptyState title="Nothing excluded" icon="fa-file-circle-check" message="No excluded files." />
            </td>
          </tr>
        </tbody>
      </table>
    </CavilListLayout>

    <div class="cavil-settings-footer">
      <SettingsLastChange :change="lastChange" empty="No changes recorded yet" />
    </div>
    <ToastNotifier ref="toaster" />
  </section>
</template>

<script>
import CavilListLayout from './CavilListLayout.vue';
import EmptyState from './EmptyState.vue';
import LegalLoading from './LegalLoading.vue';
import SettingsLastChange from './SettingsLastChange.vue';
import ToastNotifier from './ToastNotifier.vue';
import {genParamWatchers, getParams, setParam} from '../helpers/params.js';
import Refresh from '../mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'SettingsExcludedFiles',
  mixins: [Refresh],
  components: {CavilListLayout, EmptyState, LegalLoading, SettingsLastChange, ToastNotifier},
  data() {
    const params = getParams({limit: 10, offset: 0, filter: ''});
    return {
      adding: false,
      end: 0,
      exclusions: null,
      filter: params.filter,
      lastChange: null,
      params,
      refreshUrl: '/pagination/settings/excluded-files',
      rule: {package_glob: '', file: '', reason: ''},
      start: 0,
      total: 0
    };
  },
  computed: {
    canAdd() {
      return this.rule.package_glob.trim() !== '' && this.rule.file.trim() !== '';
    },
    currentPage() {
      return Math.ceil(this.end / this.params.limit);
    },
    totalPages() {
      return Math.ceil(this.total / this.params.limit);
    }
  },
  methods: {
    async add() {
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.post('/settings/excluded-files', {form: this.rule});
      if (!res.isSuccess) {
        const data = await res.json().catch(() => ({}));
        this.$refs.toaster.notify(data.error ?? 'Excluded file could not be added', 'danger', 5000);
        return;
      }
      this.adding = false;
      this.rule = {package_glob: '', file: '', reason: ''};
      this.$refs.toaster.notify('Excluded file added.');
      this.refreshNow();
    },
    filterNow() {
      this.refreshNow();
    },
    gotoPage(num) {
      this.params.offset = num * this.params.limit - this.params.limit;
      this.refreshNow();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;
      this.exclusions = data.page.map(exclusion => ({
        ...exclusion,
        created: moment(exclusion.created_epoch * 1000).fromNow()
      }));
      this.lastChange = data.last_change;
    },
    refreshNow() {
      this.cancelApiRefresh();
      this.exclusions = null;
      this.doApiRefresh();
    },
    async remove(exclusion) {
      if (!window.confirm(`Stop excluding "${exclusion.file}" for "${exclusion.package_glob}"?`)) return;
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(`/settings/excluded-files/${exclusion.id}`, {query: {_method: 'DELETE'}});
      this.refreshNow();
    }
  },
  watch: {
    ...genParamWatchers('limit', 'offset'),
    filter(val) {
      this.params.filter = val;
      this.params.offset = 0;
      setParam('filter', val);
    }
  }
};
</script>
