<template>
  <div>
    <report-metadata @reindex-queued="$refs.details.watchRebuild()" />
    <report-details ref="details" />
  </div>
</template>

<script>
import ReportDetails from './components/ReportDetails.vue';
import ReportMetadata from './components/ReportMetadata.vue';

// Root of the report page: the metadata and details areas are sibling
// components under this single app (they were two separately mounted Vue apps
// before). Each fetches and refreshes its own data independently, except for
// the Reindex button, where the report has to know right away that the rebuild
// it is about to watch was started here.
export default {
  name: 'LegalReport',
  components: {ReportDetails, ReportMetadata}
};
</script>
