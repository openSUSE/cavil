<template>
  <div>
    <div class="row mt-3">
      <div class="col-11">
        <cavil-notice-panel intro>
          These are the most recently added reviewer notes for packages you can access.
          <span v-if="canSeeLawyerOnly === true">Lawyer-only notes are shown only to lawyers and admins.</span>
        </cavil-notice-panel>
      </div>
    </div>
    <div class="row mt-3">
      <div class="col-11">
        <div class="recent-notes-filter" data-recent-notes-filter>
          <label class="recent-notes-filter-label">Filter by tag</label>
          <TagInput
            v-model="filterTags"
            :suggestions="knownTags"
            :allow-new="false"
            placeholder="Filter by tag…"
            data-key="filter"
          />
          <SegmentedControl v-model="kind" class="recent-notes-kind" label="Kind of note" :options="kinds" />
        </div>
        <ReportNotes
          endpoint="/reviews/notes/recent.json"
          :show-composer="false"
          :allow-actions="false"
          :show-package-name="true"
          :permalink-to-origin="true"
          :filter-tags="filterTags"
          :filter-kind="kind"
          empty-message="No recent notes found."
        />
      </div>
    </div>
    <BackToTop />
  </div>
</template>

<script>
import BackToTop from './components/BackToTop.vue';
import CavilNoticePanel from './components/CavilNoticePanel.vue';
import ReportNotes from './components/ReportNotes.vue';
import SegmentedControl from './components/SegmentedControl.vue';
import TagInput from './components/TagInput.vue';
import {getParams, setParam} from './helpers/params.js';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'RecentNotes',
  components: {
    BackToTop,
    CavilNoticePanel,
    ReportNotes,
    SegmentedControl,
    TagInput
  },
  data() {
    const params = getParams({tags: '', kind: ''});
    const filterTags = params.tags ? params.tags.split(',').filter(Boolean) : [];
    return {
      filterTags,
      kind: params.kind,
      knownTags: [],
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  computed: {
    kinds() {
      return [
        {value: '', label: 'All'},
        {value: 'pinned', label: 'Pinned', attrs: {'data-recent-notes-pinned': ''}},
        this.canSeeLawyerOnly && {
          value: 'lawyer_only',
          label: 'Lawyers only',
          attrs: {'data-recent-notes-lawyer-only': ''}
        },
        {value: 'limitation', label: 'Limitations', attrs: {'data-recent-notes-limitations': ''}}
      ].filter(Boolean);
    }
  },
  watch: {
    filterTags(tags) {
      setParam('tags', tags.join(','));
    },
    kind(kind) {
      setParam('kind', kind);
    }
  },
  mounted() {
    this.loadKnownTags();
  },
  methods: {
    async loadKnownTags() {
      try {
        const res = await this.ua.get('/reviews/notes/tags.json');
        if (!res.isSuccess) return;
        const data = await res.json();
        if (Array.isArray(data.tags)) this.knownTags = data.tags;
      } catch (_) {
        // Suggestions are a convenience; a failed fetch just means none are shown.
      }
    }
  }
};
</script>

<style scoped>
.recent-notes-filter {
  margin-bottom: 16px;
}
.recent-notes-kind {
  margin-top: 8px;
}
.recent-notes-filter-label {
  color: var(--cavil-fg);
  display: block;
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 6px;
}
</style>
