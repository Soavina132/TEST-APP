export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export interface Database {
  [key: string]: any;
}
