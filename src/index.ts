// eslint-disable-next-line @typescript-eslint/triple-slash-reference
/// <reference types="../types" />
import { registerPlugin } from "@capacitor/core";
import type { CapacitorMusicKitPlugin } from "./definitions";

const CapacitorMusicKit = registerPlugin<CapacitorMusicKitPlugin>(
  "CapacitorMusicKit",
  {
    web: () => import("./web").then((m) => new m.CapacitorMusicKitWeb()),
  },
);

export * from "./definitions";

// Export MusicKit types for direct import
export type Playlists = MusicKit.Playlists;
export type LibraryPlaylists = MusicKit.LibraryPlaylists;
export type Albums = MusicKit.Albums;
export type Songs = MusicKit.Songs;
export type Artists = MusicKit.Artists;
export type MusicVideos = MusicKit.MusicVideos;
export type Curators = MusicKit.Curators;
export type AppleCurators = MusicKit.AppleCurators;
export type Stations = MusicKit.Stations;
export type Genres = MusicKit.Genres;
export type Storefronts = MusicKit.Storefronts;
export type LibraryAlbums = MusicKit.LibraryAlbums;
export type LibrarySongs = MusicKit.LibrarySongs;
export type LibraryArtists = MusicKit.LibraryArtists;
export type Activities = MusicKit.Activities;
export type PersonalRecommendation = MusicKit.PersonalRecommendation;
export type RecordLabels = MusicKit.RecordLabels;
export type Ratings = MusicKit.Ratings;

export { CapacitorMusicKit };
