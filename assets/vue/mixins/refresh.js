import UserAgent from '@mojojs/user-agent';

export default {
  data() {
    return {
      params: {},
      refreshDelay: 15000,
      refreshTimer: null
    };
  },
  mounted() {
    this.doApiRefresh();
  },
  unmounted() {
    this.cancelApiRefresh();
  },
  methods: {
    async doApiRefresh() {
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.get(this.refreshUrl, {query: this.params});
      const data = await res.json();
      this.$emit('last-updated', data.last_updated);
      this.refreshData(data);
      this.refreshTimer = setTimeout(this.doApiRefresh, this.refreshDelay);
    },
    cancelApiRefresh() {
      clearTimeout(this.refreshTimer);
    }
  }
};
