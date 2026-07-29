<template>
  <div>
    <report-metadata ref="metadata" @reindex-queued="$refs.details.watchRebuild()" />
    <report-details ref="details" @rebuild-finished="$refs.metadata.rebuildFinished()" />
  </div>
</template>

<script>
import ReportDetails from './components/ReportDetails.vue';
import ReportMetadata from './components/ReportMetadata.vue';

// Root of the report page: the metadata and details areas are sibling
// components under this single app (they were two separately mounted Vue apps
// before). Each fetches and refreshes its own data independently, except
// around a rebuild: the report has to know right away that the one it is about
// to watch was started here, and the metadata has to know the moment it lands,
// because that is when the Reindex button stops having anything to offer.
export default {
  name: 'LegalReport',
  components: {ReportDetails, ReportMetadata}
};
</script>
