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
        </div>
        <ReportNotes
          endpoint="/reviews/notes/recent.json"
          :show-composer="false"
          :allow-actions="false"
          :show-package-name="true"
          :permalink-to-origin="true"
          :filter-tags="filterTags"
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
import TagInput from './components/TagInput.vue';
import {getParams, setParam} from './helpers/params.js';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'RecentNotes',
  components: {
    BackToTop,
    CavilNoticePanel,
    ReportNotes,
    TagInput
  },
  data() {
    const params = getParams({tags: ''});
    const filterTags = params.tags ? params.tags.split(',').filter(Boolean) : [];
    return {
      filterTags,
      knownTags: [],
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  watch: {
    filterTags(tags) {
      setParam('tags', tags.join(','));
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
.recent-notes-filter-label {
  color: #1f2328;
  display: block;
  font-size: 13px;
  font-weight: 600;
  margin-bottom: 6px;
}
</style>
