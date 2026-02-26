<template>
  <div class="row mt-3">
    <div class="col-md-2">
      <div class="stats">
        <div class="stats-body">{{ activePackages }}</div>
        <div class="stats-description">Active Packages</div>
      </div>
    </div>
    <div class="col-md-2">
      <div class="stats">
        <div class="stats-body">{{ openReviews }}</div>
        <div class="stats-description">Open Reviews</div>
      </div>
    </div>
    <div class="col-md-2">
      <div class="stats">
        <div class="stats-body">{{ manualReviews }}</div>
        <div class="stats-description">Manual Reviews</div>
      </div>
    </div>
    <div class="col-md-2">
      <div class="stats">
        <div class="stats-body">{{ rejectedPackages }}</div>
        <div class="stats-description">Rejected Packages</div>
      </div>
    </div>
    <div class="col-md-2">
      <div class="stats">
        <div class="stats-body">{{ embargoedPackages }}</div>
        <div class="stats-description">Embargoed Packages</div>
      </div>
    </div>
  </div>
</template>

<script>
import Refresh from './mixins/refresh.js';

export default {
  name: 'CavilStatistics',
  mixins: [Refresh],
  data() {
    return {
      activePackages: 0,
      embargoedPackages: 0,
      manualReviews: 0,
      openReviews: 0,
      refreshDelay: 120000,
      refreshUrl: '/stats/meta',
      rejectedPackages: 0
    };
  },
  methods: {
    refreshData(data) {
      this.activePackages = data.active_packages;
      this.embargoedPackages = data.embargoed_packages;
      this.openReviews = data.open_reviews;
      this.manualReviews = data.manual_reviews;
      this.rejectedPackages = data.rejected_packages;
    }
  }
};
</script>

<style>
div.stats {
  border: solid 1px #777;
  border-radius: 4px;
  box-shadow: 0 1px 1px rgba(0, 0, 0, 0.05);
  color: #777;
  margin-bottom: 20px;
}
div.stats .stats-description {
  font-size: 0.8em;
  padding: 0 15px 15px;
  text-align: center;
}
div.stats .stats-body {
  font-size: 26px;
  padding: 15px 15px 0;
  text-align: center;
}
</style>
