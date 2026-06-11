<template>
  <div v-if="closest !== null" class="closest-container">
    <div class="closest-header">
      <a :href="closest.url">
        Similar to
        <b>{{ closest.license === '' ? 'Keyword Pattern' : closest.license }}</b
        >, estimated risk {{ closest.license === '' ? 9 : closest.risk }}
      </a>
    </div>
    <div class="closest-source">
      <pre>{{ closest.text }}</pre>
    </div>
    <div class="closest-footer">
      <span v-if="closest.package !== ''"><b>Package:</b> {{ closest.package }}</span>
    </div>
  </div>
</template>

<script>
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'ClosestPattern',
  props: {
    pattern: {type: String, default: null},
    excludeId: {type: Number, default: null},
    debounceMs: {type: Number, default: 500}
  },
  emits: ['loaded'],
  data() {
    return {
      closest: null,
      ua: new UserAgent({baseURL: window.location.href}),
      debounceTimer: null,
      requestSeq: 0
    };
  },
  watch: {
    pattern() {
      this.scheduleFetch();
    }
  },
  mounted() {
    this.fetchClosest();
  },
  beforeUnmount() {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
  },
  methods: {
    scheduleFetch() {
      if (this.debounceTimer) clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(() => {
        this.debounceTimer = null;
        this.fetchClosest();
      }, this.debounceMs);
    },
    async fetchClosest() {
      const text = this.pattern;
      if (text == null || text === '') {
        this.closest = null;
        this.$emit('loaded', null);
        return;
      }
      const form = {text};
      if (this.excludeId !== null) form.exclude = String(this.excludeId);
      const seq = ++this.requestSeq;
      const res = await this.ua.post('/snippet/closest', {form});
      if (seq !== this.requestSeq) return;
      const data = await res.json();
      const pattern = data.pattern;
      if (pattern !== null) pattern.url = `/licenses/edit_pattern/${pattern.id}`;
      this.closest = pattern;
      this.$emit('loaded', pattern);
    }
  }
};
</script>

<style scoped>
.closest-container {
  border: 1px solid rgb(208, 215, 222);
  border-radius: 6px;
  margin-bottom: 1rem;
  overflow: hidden;
}
.closest-header {
  background-color: rgb(246, 248, 250);
  border-bottom: 1px solid rgb(208, 215, 222);
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
.closest-header a {
  color: #212529;
  text-decoration: none;
}
.closest-header a:hover {
  text-decoration: underline;
}
.closest-source {
  background: #fff;
  overflow: auto;
}
.closest-source pre {
  font-family: monospace;
  padding: 0 0.75rem;
  margin: 0;
  font-size: 12px;
  line-height: 20px;
  color: #24292e;
  border: 0 !important;
  white-space: -moz-pre-wrap;
  white-space: -o-pre-wrap;
  white-space: pre-wrap;
  word-wrap: break-word;
  word-break: break-all;
}
.closest-footer {
  background-color: rgb(246, 248, 250);
  border-top: 1px solid rgb(208, 215, 222);
  font-size: 13px;
  line-height: 20px;
  padding: 10px;
}
</style>
