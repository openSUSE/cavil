import Path from '@mojojs/path';
import CopyWebpackPlugin from 'copy-webpack-plugin';
import OptimizeCSSAssetsPlugin from 'css-minimizer-webpack-plugin';
import MiniCssExtractPlugin from 'mini-css-extract-plugin';
import TerserPlugin from 'terser-webpack-plugin';
import {VueLoaderPlugin} from 'vue-loader';
import webpack from 'webpack';

const assetsDir = process.env.WEBPACK_ASSETS_DIR || Path.currentFile().sibling('assets').toString();
const isDev = process.env.NODE_ENV !== 'production';

const output = {
  filename: isDev ? '[name].development.js' : '[name].[chunkhash].js',
  path: process.env.WEBPACK_OUT_DIR || Path.currentFile().sibling('public', 'asset').toString(),
  publicPath: ''
};

const entry = new Path(assetsDir, 'main.js').toString();

const minimizer = [];
if (!isDev) {
  minimizer.push(new TerserPlugin({parallel: true}));
  minimizer.push(new OptimizeCSSAssetsPlugin({}));
}

const rules = [];

rules.push({
  test: /\.js$/,
  exclude: /node_modules/,
  use: {
    loader: 'babel-loader',
    options: {
      plugins: ['@babel/plugin-transform-runtime'],
      presets: ['@babel/preset-env']
    }
  }
});

rules.push({
  test: /\.css$/,
  use: [MiniCssExtractPlugin.loader, {loader: 'css-loader', options: {sourceMap: true, url: false}}]
});

rules.push({test: /\.vue$/, use: 'vue-loader'});

rules.push({
  test: /\.s(a|c)ss$/,
  use: [
    MiniCssExtractPlugin.loader,
    {loader: 'css-loader', options: {sourceMap: true, url: false}},
    {loader: 'sass-loader', options: {sourceMap: true}}
  ]
});

const config = {
  entry: {cavil: entry},
  mode: isDev ? 'development' : 'production',
  module: {rules},
  optimization: {minimizer},
  output,
  plugins: [
    new CopyWebpackPlugin({
      patterns: [{from: './node_modules/@fortawesome/fontawesome-free/webfonts', to: './webfonts'}]
    }),
    new MiniCssExtractPlugin({filename: isDev ? '[name].development.css' : '[name].[contenthash].css'}),
    new VueLoaderPlugin(),
    new webpack.DefinePlugin({
      __VUE_OPTIONS_API__: 'true',
      __VUE_PROD_DEVTOOLS__: 'false'
    })
  ]
};

export default config;
