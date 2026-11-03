<template>
  <section>
    <div class="cavil-settings-header">
      <h3>Data retention</h3>
      <p>Decide how long the source code and reports of reviews are kept before cleanup removes them.</p>
      <p>
        Changes take effect with the next scheduled cleanup. Reviews that are part of a product or still wait for a
        decision are always kept.
      </p>
    </div>

    <LegalLoading v-if="form === null" message="Loading settings..." size="small" />
    <form v-else @submit.prevent="save()">
      <div v-for="field in fields" :key="field.name" class="cavil-settings-rule">
        <label :for="field.id" class="cavil-settings-label">{{ field.label }}</label>
        <SettingsDefaultLabel :name="field.name" :custom="custom" @reset="reset" />
        <p class="cavil-settings-help">{{ field.help }}</p>
        <div class="cavil-settings-nested">
          <div class="input-group cavil-settings-number">
            <input :id="field.id" v-model.number="form[field.name]" type="number" min="1" class="form-control" />
            <span class="input-group-text">{{ field.unit }}</span>
          </div>
          <div v-if="errors[field.name]" class="cavil-settings-error">{{ errors[field.name] }}</div>
        </div>
      </div>

      <div class="cavil-settings-footer">
        <button type="submit" class="btn btn-success" id="settings-save" :disabled="!dirty || saving">
          Save changes
        </button>
        <SettingsLastChange :change="lastChange" empty="Using default values" />
      </div>
    </form>
    <ToastNotifier ref="toaster" />
  </section>
</template>

<script>
import LegalLoading from './LegalLoading.vue';
import SettingsDefaultLabel from './SettingsDefaultLabel.vue';
import SettingsLastChange from './SettingsLastChange.vue';
import ToastNotifier from './ToastNotifier.vue';
import SettingsForm from '../mixins/settingsForm.js';

export default {
  name: 'SettingsRetention',
  components: {LegalLoading, SettingsDefaultLabel, SettingsLastChange, ToastNotifier},
  mixins: [SettingsForm],
  data() {
    return {
      settingsUrl: '/settings/retention.json',
      fields: [
        {
          name: 'days_to_keep_orphaned_packages',
          id: 'days-to-keep-orphaned-packages',
          label: 'Keep finished reviews',
          help: 'Reviews that have been decided and are not part of a product.',
          unit: 'days'
        },
        {
          name: 'days_to_keep_orphaned_duplicate_packages',
          id: 'days-to-keep-orphaned-duplicate-packages',
          label: 'Keep older versions of finished reviews',
          help: 'Once a newer version of the same package has been reviewed, older ones can go sooner.',
          unit: 'days'
        },
        {
          name: 'hours_to_keep_ephemeral_packages',
          id: 'hours-to-keep-ephemeral-packages',
          label: 'Keep one-off reviews',
          help: 'Ephemeral reviews uploaded for a quick check are removed completely after this time.',
          unit: 'hours'
        }
      ]
    };
  }
};
</script>
