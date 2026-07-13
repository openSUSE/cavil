<template>
  <div>
    <report-metadata />
    <report-details />
  </div>
</template>

<script>
import ReportDetails from './components/ReportDetails.vue';
import ReportMetadata from './components/ReportMetadata.vue';

// Root of the report page: the metadata and details areas are sibling
// components under this single app (they were two separately mounted Vue apps
// before). Each fetches and refreshes its own data independently.
export default {
  name: 'LegalReport',
  components: {ReportDetails, ReportMetadata}
};
</script>
