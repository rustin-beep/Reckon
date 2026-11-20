package main

import (
	"reflect"
	"testing"
)

func TestDepsFromManifest(t *testing.T) {
	cases := []struct {
		name string
		src  string
		want []string
	}{
		{
			name: "no imports",
			src:  "name = \"vitro/reckon\"\nversion = \"0.1.0\"\n",
			want: nil,
		},
		{
			name: "block form",
			src:  "name = \"a/b\"\n\nimport {\n  \"moonbitlang/x@0.4.6\",\n  \"moonbit-community/foo\",\n}\n",
			want: []string{"moonbitlang/x@0.4.6", "moonbit-community/foo"},
		},
		{
			name: "single line form",
			src:  "import { \"moonbitlang/x\" }\n",
			want: []string{"moonbitlang/x"},
		},
		{
			name: "quoted strings outside import are ignored",
			src:  "name = \"evil/pkg\"\ndescription = \"mentions \\\"other/pkg\\\"\"\n",
			want: nil,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := depsFromManifest(tc.src)
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("depsFromManifest() = %#v, want %#v", got, tc.want)
			}
		})
	}
}

func TestForbidden(t *testing.T) {
	cases := []struct {
		name string
		deps []string
		want []string
	}{
		{
			name: "allowed namespaces",
			deps: []string{"moonbitlang/x@0.4.6", "moonbit-community/abc"},
			want: nil,
		},
		{
			name: "third party",
			deps: []string{"caimeox/evmasm"},
			want: []string{"caimeox/evmasm"},
		},
		{
			name: "official member personal package is still third party",
			deps: []string{"moonbitlang/x", "someone/thing"},
			want: []string{"someone/thing"},
		},
		{
			name: "prefix must be a namespace, not a substring",
			deps: []string{"moonbitlangx/foo", "moonbit-communityx/foo"},
			want: []string{"moonbitlangx/foo", "moonbit-communityx/foo"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := forbidden(tc.deps)
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("forbidden() = %#v, want %#v", got, tc.want)
			}
		})
	}
}
