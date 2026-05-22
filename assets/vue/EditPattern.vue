<template>
  <div class="edit-pattern">
    <div v-if="!isNew" class="row">
      <div class="col mb-3 edit-pattern-match-count">
        <span v-if="matchCount === null && matchCountError === null">
          <i class="fa-solid fa-rotate fa-spin"></i> Loading match count
        </span>
        <span v-else-if="matchCountError !== null" class="text-danger">{{ matchCountError }}</span>
        <span v-else-if="matchCount.matches === 0">This pattern has no matches.</span>
        <span v-else>
          This pattern has <b>{{ matchCount.matches }}</b> {{ matchCount.matches === 1 ? 'match' : 'matches' }} in
          <b>{{ matchCount.packages }}</b>
          <a :href="`/search?pattern=${pattern.id}`">{{ matchCount.packages === 1 ? 'package' : 'packages' }}</a
          >.
        </span>
      </div>
    </div>

    <div class="row">
      <form :action="formAction" method="POST">
        <div class="col mb-3">
          <label class="form-label" for="license">License</label>
          <input v-model="form.license" type="text" name="license" id="license" class="form-control" />
        </div>
        <div v-if="!isNew" class="col mb-3">
          <label class="form-label" for="spdx">SPDX</label>
          <input :value="pattern.spdx" type="text" id="spdx" class="form-control" disabled />
        </div>
        <div class="col mb-3">
          <label class="form-label" for="pattern-text">Pattern</label>
          <PatternCodeMirror v-model="form.pattern" />
          <textarea ref="patternMirror" name="pattern" :value="form.pattern" class="edit-pattern-hidden"></textarea>
        </div>

        <div class="col mb-3">
          <div class="row">
            <div class="col-lg-2 mb-3">
              <div class="form-floating">
                <select v-model="form.risk" name="risk" id="risk" class="form-control">
                  <option v-for="r in 10" :key="r - 1" :value="String(r - 1)">{{ r - 1 }}</option>
                </select>
                <label for="risk" class="form-label">Risk</label>
              </div>
            </div>
            <div class="col-lg-2">
              <div class="form-check">
                <input
                  v-model="form.patent"
                  type="checkbox"
                  class="form-check-input"
                  id="patent"
                  name="patent"
                  value="1"
                />
                <label class="form-check-label" for="patent">Patent</label>
              </div>
              <div class="form-check">
                <input
                  v-model="form.trademark"
                  type="checkbox"
                  class="form-check-input"
                  id="trademark"
                  name="trademark"
                  value="1"
                />
                <label class="form-check-label" for="trademark">Trademark</label>
              </div>
            </div>
            <div class="col-lg-2">
              <div class="form-check">
                <input
                  v-model="form.export_restricted"
                  type="checkbox"
                  class="form-check-input"
                  id="export_restricted"
                  name="export_restricted"
                  value="1"
                />
                <label class="form-check-label" for="export_restricted">Export Restricted</label>
              </div>
            </div>
          </div>
        </div>

        <div class="col mb-3">
          <label class="form-label" for="packname">Package</label>
          <input v-model="form.packname" type="text" name="packname" id="packname" class="form-control" />
          <div id="packageHelp" class="form-text">Leave this field empty to apply pattern to all packages</div>
        </div>

        <div class="col mb-5">
          <button type="submit" class="btn btn-primary">{{ isNew ? 'Create' : 'Update' }}</button>
          <button v-if="!isNew" type="button" class="del-pattern btn btn-danger btn-sm" @click="onDelete">
            Delete
          </button>
        </div>
      </form>
    </div>

    <ClosestPattern :pattern="form.pattern" :exclude-id="pattern.id ?? null" />
  </div>
</template>

<script>
import ClosestPattern from './components/ClosestPattern.vue';
import PatternCodeMirror from './components/PatternCodeMirror.vue';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'EditPattern',
  components: {ClosestPattern, PatternCodeMirror},
  data() {
    const pattern = this.currentPattern;
    return {
      pattern,
      form: {
        license: pattern.license ?? '',
        pattern: pattern.pattern ?? '',
        risk: String(pattern.risk ?? 0),
        patent: !!pattern.patent,
        trademark: !!pattern.trademark,
        export_restricted: !!pattern.export_restricted,
        packname: pattern.packname ?? ''
      },
      matchCount: null,
      matchCountError: null,
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  computed: {
    isNew() {
      return this.pattern.id == null;
    },
    formAction() {
      return this.isNew ? '/licenses/create_pattern' : `/licenses/update_pattern/${this.pattern.id}`;
    }
  },
  mounted() {
    if (!this.isNew) this.loadMatchCount();
  },
  methods: {
    async loadMatchCount() {
      try {
        const res = await this.ua.get(`/licenses/pattern/${this.pattern.id}/match_count.json`);
        if (!res.isSuccess) throw new Error(`HTTP ${res.statusCode}`);
        this.matchCount = await res.json();
      } catch (e) {
        this.matchCountError = 'Could not load match count.';
      }
    },
    async onDelete() {
      if (!window.confirm('Sure to delete pattern?')) return;
      const res = await this.ua.delete(`/licenses/remove_pattern/${this.pattern.id}`);
      if (res.isSuccess) {
        window.location = '/licenses';
      } else {
        window.alert('Failed to delete pattern.');
      }
    }
  }
};
</script>

<style scoped>
.edit-pattern-match-count {
  min-height: 1.5rem;
}
.edit-pattern-hidden {
  display: none;
}
.del-pattern {
  margin-left: 0.5rem;
}
</style>
