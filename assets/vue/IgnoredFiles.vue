<template>
  <div>
    <div class="row mt-3">
      <cavil-notice-panel intro class="col-12">
        These globs are used to decide which files the indexer should ignore when scanning for license pattern matches.
        <button name="add-glob" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#globModal">
          Add Glob
        </button>
      </cavil-notice-panel>
    </div>
    <CavilListLayout
      :current-page="currentPage"
      :end="end"
      :filter="filter"
      count-icon="fa-solid fa-file-shield"
      filter-aria-label="Ignored file filters"
      filter-input-id="ignored-files-filter-input"
      filter-label="Filter globs"
      filter-placeholder="Filter globs"
      plural="ignored file globs"
      singular="ignored file glob"
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
            <th>Glob</th>
            <th>Created</th>
            <th>Owner</th>
            <th>Contributor</th>
            <th></th>
          </tr>
        </thead>
        <tbody v-if="globs === null">
          <tr>
            <td id="all-done" colspan="5" class="cavil-list-state">
              <LegalLoading message="Loading globs..." size="small" />
            </td>
          </tr>
        </tbody>
        <tbody v-else-if="globs.length > 0">
          <tr v-for="glob in globs" :key="glob.id">
            <td>
              <span class="cavil-list-token">{{ glob.glob }}</span>
            </td>
            <td class="relative-time cavil-list-time">{{ glob.created }}</td>
            <td>{{ glob.login }}</td>
            <td>{{ glob.contributor }}</td>
            <td class="text-center">
              <button
                @click="deleteGlob(glob)"
                type="button"
                class="cavil-icon-action cavil-icon-action-danger"
                title="Delete ignored file glob"
                aria-label="Delete ignored file glob"
              >
                <i class="fa-solid fa-trash"></i>
              </button>
            </td>
          </tr>
        </tbody>
        <tbody v-else>
          <tr>
            <td id="all-done" colspan="5" class="cavil-list-empty-cell">
              <EmptyState message="No ignored file globs found." />
            </td>
          </tr>
        </tbody>
      </table>
    </CavilListLayout>
    <div class="modal fade" id="globModal" tabindex="-1" aria-labelledby="globModalLabel" aria-hidden="true">
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title" id="globModalLabel">Add Glob</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body">
            <form>
              <div class="mb-3">
                <label for="glob-to-add" class="col-form-label">Glob</label>
                <input v-model="globToAdd" class="form-control" id="glob-to-add" />
              </div>
            </form>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
            <button @click="addGlob()" type="button" id="globAddButton" class="btn btn-primary" data-bs-dismiss="modal">
              Add
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import CavilListLayout from './components/CavilListLayout.vue';
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import EmptyState from './components/EmptyState.vue';
import LegalLoading from './components/LegalLoading.vue';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'IgnoredFiles',
  mixins: [Refresh],
  components: {CavilListLayout, CavilNoticePanel, EmptyState, LegalLoading},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      filter: ''
    });

    return {
      addGlobUrl: '/ignored-files',
      end: 0,
      globs: null,
      globToAdd: '',
      params,
      refreshUrl: '/pagination/files/ignored',
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
    async addGlob() {
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(this.addGlobUrl, {form: {glob: this.globToAdd}});
      this.doApiRefresh();
    },
    async deleteGlob(glob) {
      const ua = new UserAgent({baseURL: window.location.href});
      await ua.post(glob.removeUrl, {query: {_method: 'DELETE'}});
      this.doApiRefresh();
    },
    gotoPage(num) {
      this.cancelApiRefresh();
      const limit = this.params.limit;
      this.params.offset = num * limit - limit;
      this.globs = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      const globs = [];
      for (const glob of data.page) {
        globs.push({
          id: glob.id,
          glob: glob.glob,
          created: moment(glob.created_epoch * 1000).fromNow(),
          login: glob.login,
          contributor: glob.contributor_login ?? '',
          removeUrl: `/ignored-files/${glob.id}`
        });
      }
      this.globs = globs;
    },
    filterNow() {
      this.cancelApiRefresh();
      this.globs = null;
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
