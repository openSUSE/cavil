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
        <ReportNotes
          endpoint="/reviews/notes/recent.json"
          :show-composer="false"
          :allow-actions="false"
          :show-package-name="true"
          :permalink-to-origin="true"
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

export default {
  name: 'RecentNotes',
  components: {
    BackToTop,
    CavilNoticePanel,
    ReportNotes
  }
};
</script>
