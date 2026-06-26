<template>
  <div class="stats-dashboard mt-3">
    <donut-stat-tile
      title="Package activity"
      :total="activePackages"
      total-label="active packages"
      center-label="reviewed"
      :center-value="reviewedPackages"
      :slices="packageActivitySlices"
    ></donut-stat-tile>
    <donut-stat-tile
      title="Review automation"
      :total="performedReviews"
      total-label="performed reviews"
      center-label="automated"
      :center-value="displayedAutomatedReviews"
      :slices="reviewAutomationSlices"
    >
      <template #actions>
        <div class="stats-scope-toggle" aria-label="Review automation scope">
          <button type="button" :class="{active: reviewScope === 'overall'}" @click="reviewScope = 'overall'">
            Overall
          </button>
          <button type="button" :class="{active: reviewScope === 'month'}" @click="reviewScope = 'month'">Month</button>
        </div>
      </template>
    </donut-stat-tile>
    <number-stat-tile
      v-for="tile in numberTiles"
      :key="tile.label"
      :label="tile.label"
      :value="tile.value"
    ></number-stat-tile>
    <package-activity-tile
      subtitle="past 24 hours"
      label-mode="hourly"
      :series="importedActivity"
    ></package-activity-tile>
    <package-activity-tile
      subtitle="past week"
      label-mode="weekly"
      :series="weeklyImportedActivity"
    ></package-activity-tile>
  </div>
</template>

<script>
import DonutStatTile from './components/DonutStatTile.vue';
import NumberStatTile from './components/NumberStatTile.vue';
import PackageActivityTile from './components/PackageActivityTile.vue';
import Refresh from './mixins/refresh.js';

export default {
  name: 'CavilStatistics',
  components: {DonutStatTile, NumberStatTile, PackageActivityTile},
  mixins: [Refresh],
  data() {
    return {
      activePackages: 0,
      automatedReviews: 0,
      embargoedPackages: 0,
      importedActivity: [],
      manualReviews: 0,
      monthlyAutomatedReviews: 0,
      monthlyManualReviews: 0,
      monthlyPerformedReviews: 0,
      openReviews: 0,
      performedReviewsOverall: 0,
      refreshDelay: 120000,
      refreshUrl: '/stats/meta',
      rejectedPackages: 0,
      reviewScope: 'overall',
      totalSnippets: 0,
      totalLicensePatterns: 0,
      unresolvedMatches: 0,
      weeklyImportedActivity: []
    };
  },
  computed: {
    packageActivitySlices() {
      return [
        {label: 'open reviews', value: this.openReviews, color: '#0969da'},
        {label: 'rejected packages', value: this.rejectedPackages, color: '#cf222e'}
      ];
    },
    reviewedPackages() {
      return Math.max(this.activePackages - this.openReviews, 0);
    },
    performedReviews() {
      if (this.reviewScope === 'month') return this.monthlyPerformedReviews;

      return this.performedReviewsOverall;
    },
    displayedManualReviews() {
      return this.reviewScope === 'month' ? this.monthlyManualReviews : this.manualReviews;
    },
    displayedAutomatedReviews() {
      return this.reviewScope === 'month' ? this.monthlyAutomatedReviews : this.automatedReviews;
    },
    reviewAutomationSlices() {
      return [
        {label: 'manual reviews', value: this.displayedManualReviews, color: '#8250df'},
        {label: 'automated reviews', value: this.displayedAutomatedReviews, color: '#1f883d'}
      ];
    },
    numberTiles() {
      return [
        {label: 'Unresolved Matches', value: this.unresolvedMatches},
        {label: 'Snippets', value: this.totalSnippets},
        {label: 'License Patterns', value: this.totalLicensePatterns},
        {label: 'Embargoed Packages', value: this.embargoedPackages}
      ];
    }
  },
  methods: {
    refreshData(data) {
      this.activePackages = data.active_packages;
      this.automatedReviews = data.automated_reviews;
      this.embargoedPackages = data.embargoed_packages;
      this.importedActivity = data.imported_activity;
      this.openReviews = data.open_reviews;
      this.manualReviews = data.manual_reviews;
      this.monthlyAutomatedReviews = data.monthly_automated_reviews;
      this.monthlyManualReviews = data.monthly_manual_reviews;
      this.monthlyPerformedReviews = data.monthly_performed_reviews;
      this.performedReviewsOverall = data.performed_reviews;
      this.rejectedPackages = data.rejected_packages;
      this.totalSnippets = data.total_snippets;
      this.totalLicensePatterns = data.total_license_patterns;
      this.unresolvedMatches = data.unresolved_matches;
      this.weeklyImportedActivity = data.weekly_imported_activity;
    }
  }
};
</script>

<style>
.stats-dashboard {
  display: grid;
  gap: 1rem;
  grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
}

.stats-scope-toggle {
  align-self: flex-start;
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  border-radius: 6px;
  display: inline-flex;
  margin-top: 0.65rem;
  padding: 2px;
  width: max-content;
}

.stats-scope-toggle button {
  background: transparent;
  border: 0;
  border-radius: 4px;
  color: #57606a;
  font-size: 0.75rem;
  font-weight: 600;
  line-height: 1.25;
  padding: 0.3rem 0.55rem;
}

.stats-scope-toggle button.active {
  background: #fff;
  box-shadow: 0 1px 2px rgba(27, 31, 36, 0.08);
  color: #24292f;
}
</style>
