<template>
  <div v-if="components.length > 0">
    <h2>
      <a href="#components" data-bs-toggle="collapse">{{ components.length }} {{ components.length === 1 ? 'Component' : 'Components' }}</a>
    </h2>
    <div class="row collapse" id="components">
      <div class="col">
        <table class="table table-striped table-hover transparent-table">
          <thead>
            <tr>
              <th>Ecosystem</th>
              <th>Name</th>
              <th>Version</th>
              <th>License</th>
              <th>Manifest</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="component in components" :key="component.id">
              <td>{{ component.ecosystem }}</td>
              <td>{{ component.name }}</td>
              <td>{{ component.version || '-' }}</td>
              <td>{{ component.license || 'NOASSERTION' }}</td>
              <td class="text-muted small">{{ component.manifest_path }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'ComponentList',
  props: {
    components: {
      type: Array,
      required: true
    }
  }
};
</script>
