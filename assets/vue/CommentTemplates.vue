<template>
  <div>
    <div class="row mt-3">
      <cavil-notice-panel intro class="col-12">
        These templates prefill the review comment box on report pages. Reviewers pick one from the editor and replace
        the [PLACEHOLDER] tokens, so recurring instructions only have to be written once.
        <template #actions>
          <button name="add-template" class="btn btn-primary" @click="startAdd()">Add Template</button>
        </template>
      </cavil-notice-panel>
    </div>

    <div v-if="editing !== null" class="row mt-3">
      <div class="col-12 comment-template-form">
        <div class="mb-3">
          <label for="template-name" class="form-label">Name</label>
          <input v-model="editing.name" class="form-control" id="template-name" placeholder="Unacceptable-File" />
        </div>
        <!-- Placeholders are authored here, not filled in, so clicking one must not select it -->
        <CommentEditor v-model="editing.body" :interactive="false" label="Body" />
        <div class="comment-template-form-footer">
          <span class="comment-template-placeholder-count">{{ placeholderSummary }}</span>
          <button type="button" class="btn btn-secondary" id="template-cancel" @click="editing = null">Cancel</button>
          <button type="button" class="btn btn-primary" id="template-save" :disabled="!canSave" @click="saveTemplate()">
            Save
          </button>
        </div>
      </div>
    </div>

    <CavilListLayout
      :current-page="currentPage"
      :end="end"
      :filter="filter"
      count-icon="fa-solid fa-comment-dots"
      filter-aria-label="Comment template filters"
      filter-input-id="comment-templates-filter-input"
      filter-label="Filter templates"
      filter-placeholder="Filter templates"
      plural="comment templates"
      singular="comment template"
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
            <th>Name</th>
            <th>Body</th>
            <th>Author</th>
            <th>Created</th>
            <th>Edited</th>
            <th></th>
          </tr>
        </thead>
        <tbody v-if="templates === null">
          <tr>
            <td id="all-done" colspan="6" class="cavil-list-state">
              <LegalLoading message="Loading templates..." size="small" />
            </td>
          </tr>
        </tbody>
        <tbody v-else-if="templates.length > 0">
          <tr v-for="template in templates" :key="template.id">
            <td>
              <span class="cavil-list-token">{{ template.name }}</span>
            </td>
            <td class="cavil-list-comment">
              <div class="cavil-list-comment-body">
                <span class="comment-template-preview">{{ template.preview }}</span>
              </div>
            </td>
            <td>{{ template.author }}</td>
            <td class="relative-time cavil-list-time">{{ template.created }}</td>
            <td class="relative-time cavil-list-time">{{ template.edited }}</td>
            <td class="text-center">
              <button
                @click="startEdit(template)"
                type="button"
                class="cavil-icon-action"
                title="Edit comment template"
                aria-label="Edit comment template"
              >
                <i class="fa-solid fa-pen"></i>
              </button>
              <button
                @click="deleteTemplate(template)"
                type="button"
                class="cavil-icon-action cavil-icon-action-danger"
                title="Delete comment template"
                aria-label="Delete comment template"
              >
                <i class="fa-solid fa-trash"></i>
              </button>
            </td>
          </tr>
        </tbody>
        <tbody v-else>
          <tr>
            <td id="all-done" colspan="6" class="cavil-list-empty-cell">
              <EmptyState message="No comment templates found." />
            </td>
          </tr>
        </tbody>
      </table>
    </CavilListLayout>
    <ToastNotifier ref="toaster" />
  </div>
</template>

<script>
import CavilListLayout from './components/CavilListLayout.vue';
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import CommentEditor from './components/CommentEditor.vue';
import EmptyState from './components/EmptyState.vue';
import LegalLoading from './components/LegalLoading.vue';
import ToastNotifier from './components/ToastNotifier.vue';
import {findPlaceholders} from './helpers/placeholders.js';
import {genParamWatchers, getParams, setParam} from './helpers/params.js';
import Refresh from './mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

export default {
  name: 'CommentTemplates',
  mixins: [Refresh],
  components: {CavilListLayout, CavilNoticePanel, CommentEditor, EmptyState, LegalLoading, ToastNotifier},
  data() {
    const params = getParams({
      limit: 10,
      offset: 0,
      filter: ''
    });

    return {
      editing: null,
      end: 0,
      params,
      refreshUrl: '/pagination/comment-templates',
      filter: params.filter,
      start: 0,
      templates: null,
      total: 0
    };
  },
  computed: {
    canSave() {
      return this.editing !== null && this.editing.name.trim() !== '' && this.editing.body.trim() !== '';
    },
    currentPage() {
      return Math.ceil(this.end / this.params.limit);
    },
    // Confirmation that the placeholder syntax parsed the way the author meant it to
    placeholderSummary() {
      if (this.editing === null) return '';
      const found = findPlaceholders(this.editing.body);
      if (found.length === 0) return 'No placeholders';
      return found.length === 1 ? '1 placeholder' : `${found.length} placeholders`;
    },
    totalPages() {
      return Math.ceil(this.total / this.params.limit);
    }
  },
  methods: {
    async deleteTemplate(template) {
      if (!window.confirm(`Delete the comment template "${template.name}"?`)) return;
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.post(`/comment-templates/${template.id}`, {query: {_method: 'DELETE'}});
      if (!res.isSuccess) {
        this.$refs.toaster?.notify(`Could not delete template (HTTP ${res.statusCode})`, 'danger', 5000);
        return;
      }
      this.$refs.toaster?.notify(`Deleted ${template.name}`);
      this.doApiRefresh();
    },
    filterNow() {
      this.cancelApiRefresh();
      this.templates = null;
      this.doApiRefresh();
    },
    gotoPage(num) {
      this.cancelApiRefresh();
      const limit = this.params.limit;
      this.params.offset = num * limit - limit;
      this.templates = null;
      this.doApiRefresh();
    },
    refreshData(data) {
      this.start = data.start;
      this.end = data.end;
      this.total = data.total;

      const templates = [];
      for (const template of data.page) {
        templates.push({
          id: template.id,
          name: template.name,
          body: template.body,
          // Only three lines are shown, so blank lines would waste two of them
          preview: template.body.replace(/\n{2,}/g, '\n'),
          // Templates that shipped with Cavil have no author
          author: template.login ?? 'system',
          created: moment(template.created_epoch * 1000).fromNow(),
          edited: template.edited_epoch === null ? '' : moment(template.edited_epoch * 1000).fromNow()
        });
      }
      this.templates = templates;
    },
    async saveTemplate() {
      const template = this.editing;
      const ua = new UserAgent({baseURL: window.location.href});
      const form = {name: template.name.trim(), body: template.body};
      const res =
        template.id === null
          ? await ua.post('/comment-templates', {form})
          : await ua.post(`/comment-templates/${template.id}`, {form, query: {_method: 'PUT'}});

      let data = null;
      try {
        data = await res.json();
      } catch (e) {
        // Not JSON, an authentication failure renders an HTML page
      }
      if (!res.isSuccess) {
        const message = (data && data.error) || `Request failed (HTTP ${res.statusCode})`;
        this.$refs.toaster?.notify(message, 'danger', 5000);
        return;
      }

      this.$refs.toaster?.notify(`Saved ${form.name}`);
      this.editing = null;
      this.doApiRefresh();
    },
    startAdd() {
      this.editing = {id: null, name: '', body: ''};
    },
    startEdit(template) {
      this.editing = {id: template.id, name: template.name, body: template.body};
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

<style scoped>
/* A full template body would make every row several times taller than the rest of the table. The clamp
   lives on an inner element, otherwise the clipped fourth line bleeds into the quote box padding. */
.comment-template-preview {
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 3;
  display: -webkit-box;
  overflow: hidden;
}
.comment-template-form-footer {
  align-items: center;
  display: flex;
  gap: 0.5rem;
  justify-content: flex-end;
  margin-top: 0.75rem;
}
.comment-template-placeholder-count {
  color: #57606a;
  font-size: 13px;
  margin-right: auto;
}
</style>
